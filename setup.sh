#!/bin/bash
# -------------------- Time tracking, signal trapping, and requeue functions  ------------------------ 
secs2timestr() {
 ((h=${1}/3600))
 ((m=(${1}%3600)/60))
 ((s=${1}%60))
 printf "%02d:%02d:%02d\n" $h $m $s
}

timestr2secs() {
echo $1| sed 's/-/:/' | awk -F: '{print $4, $3, $2, $1}'|awk '{print $1+60*$2+3600*$3+86400*$4}'
}

parse_job(){

    #set default
    #read <sig_time> from the job script 
    if [[ -z $ckpt_overhead ]]; then 
        jscript=/var/spool/slurmd/job$SLURM_JOB_ID/slurm_script
        if [[ -f $jscript ]]; then
            x=`grep "#SBATCH*.--signal=" $jscript|grep -v "#*.#SBATCH"| tail -1 |awk -F@ '{print $2}'`
            if [[ -n $x ]]; then let ckpt_overhead=$x; fi
        fi
    fi  
    
    if [[ -z $ckpt_overhead ]]; then let ckpt_overhead=300; fi
    if [[ -z $max_timelimit ]]; then let max_timelimit=172800; fi


    TOTAL_TIME=$(squeue -h -j $SLURM_JOB_ID -o %k)
    timeAlloc=$(squeue -h -j $SLURM_JOB_ID -o %l)

    fields=`echo $timeAlloc | awk -F ':' '{print NF}'`
    if [ $fields -le 2 ]; then
       timeAlloc=`echo 0:$timeAlloc`
    fi

    timeAlloc=`timestr2secs $timeAlloc`
    TOTAL_TIME=`timestr2secs $TOTAL_TIME`

    let remainingTimeSec=TOTAL_TIME-timeAlloc+ckpt_overhead
    if [ $remainingTimeSec -gt 0 ]; then
        remainingTime=`secs2timestr $remainingTimeSec`
        scontrol update JobId=$SLURM_JOB_ID Comment=$remainingTime

        let maxtime=`timestr2secs $max_timelimit`
        if [ $remainingTimeSec -gt $maxtime ]; then 
           requestTime=$max_timelimit
        else
           requestTime=$remainingTime
        fi
        echo time remaining \$remainingTime: $remainingTime >&2
        echo next timelimit \$requestTime: $requestTime >&2
    fi
    requestTime=$((requestTime/60))        #convert to minutes instead of seconds
}

requeue_job() {

    parse_job

    if [ -n $remainingTimeSec ] && [ $remainingTimeSec -gt 0 ]; then
        func="$1" ; shift
        for sig ; do
            trap "$func $sig" "$sig"
        done
    else
       echo no more job requeues,done! >&2
    fi
}

func_trap() {
######################################################
# -------------- checkpoint application --------------
######################################################
    # insert checkpoint command here if any
    set -x
    $ckpt_command >&2
    trap '' SIGTERM
    scontrol requeue ${SLURM_JOB_ID} >&2
    scontrol update JobId=${SLURM_JOB_ID} TimeLimit=${requestTime} >&2
    trap - SIGTERM
    echo \$?: $? >&2
    set +x
}

# Create dmtcp_command wrapper for easy communication with coordinator
dmtcp_command_job () {
    fname=dmtcp_command.$SLURM_JOB_ID	
    h=$1
    p=$2
    str="#!/bin/bash
    export PATH=$PATH
    export DMTCP_COORD_HOST=$h
    export DMTCP_COORD_PORT=$p
    dmtcp_command \$@"
    echo "$str" >$fname
    chmod a+rx $fname

}

restart_count () {
	echo ${SLURM_RESTART_COUNT:-0}
}

#----------------------------- Set up DMTCP environment for a job ------------#
start_coordinator()
{
    fname=dmtcp_command.$SLURM_JOBID
    h=`hostname`

    check_coordinator=`which dmtcp_coordinator`
    if [ -z "$check_coordinator" ]; then
        echo "No dmtcp_coordinator found. Check your DMTCP installation and PATH settings." >&2
        exit 0
    fi

    dmtcp_coordinator --daemon --exit-on-last -p 0 --port-file $fname $@ 1>/dev/null 2>&1

    while true; do
        if [ -f "$fname" ]; then
            p=`cat $fname`
            if [ -n "$p" ]; then
                break
            fi
        fi
    done
    export DMTCP_COORD_HOST=$h
    export DMTCP_COORD_PORT=$p

    # Create dmtcp_command wrapper for easy communication with coordinator
    p=`cat $fname`
    str="#!/bin/bash
    export PATH=$PATH 
    export DMTCP_COORD_HOST=$h
    export DMTCP_COORD_PORT=$p
    dmtcp_command \$@"
    echo "$str" >$fname
    chmod a+rx $fname

    #log dmtcp
    echo $SLURM_JOB_ID $USER `date +%F` $(restart_count)  >> /usr/common/software/spool/dmtcp_command.log 
}

#wait for a process to complete
wait_pid () {
    pid=$1
    while [ -e /proc/$pid ]
    do
        sleep 1
    done
}

##function cr_run () {

###max_timelimit=00:02:30
###ckpt_overhead=30
###start_coordinator -i 30
##start_coordinator --exit-after-ckpt

##let restart_count=`squeue -h -O restartcnt -j $SLURM_JOB_ID`
##if (( restart_count == 0 )); then
##    dmtcp_launch --ckpt-signal 10 $@
##elif (( $restart_count > 0 )) && [[ -e dmtcp_restart_script.sh ]]; then
##    bash ./dmtcp_restart_script.sh -h $DMTCP_COORD_HOST -p $DMTCP_COORD_PORT
##else
##    echo "Failed to restart the job, exit"
##    exit
##fi
##}

append_testpath () {
    #export PATH=${PATH}:$DMTCP_DIR/test
    export PATH=${PATH}:/global/common/sw/cray/cnl7/haswell/dmtcp/2019-10-24/test
}

prepend_testpath () {
    #export PATH=$DMTCP_DIR/test:$PATH
    export PATH=/global/common/sw/cray/cnl7/haswell/dmtcp/2019-10-24/test:$PATH
}

#wait for coordinator to complete checkpointing
wait_coord () {
    let sum=0
    ckpt_done=0
    while true; do
        x=(`dmtcp_command.$SLURM_JOB_ID -s`)
        npeers=${x[6]/#*=/}
        running=${x[7]/#*=/}
        if [[ $npeers > 0 ]] && [[ $running == no ]] ; then
	    let sum=sum+1
            sleep 1
        elif [[ $npeers > 0 ]] && [[ $running == yes ]] ; then
	    ckpt_done=1
	    break
        else
	    break
	fi
    done
    if [[ $ckpt_done == 1 ]]; then
        echo checkpointing completed, overhead =  $sum seconds >&2
    else
	echo no running job to checkpoint >&2
    fi
}

#checkpoint before before requeue the job
ckpt_dmtcp () {
    dmtcp_command.$SLURM_JOB_ID -c 
    wait_coord
}

#update VASP INCAR
function update_incar () {
tag=$1
infile=INCAR
outfile=OUTCAR

if [[ $tag == NSW ]]; then

if [[ ! -f $infile ]] ; then
echo no $infile is present, exit
return 1
fi

if [[ ! -f $outfile ]]; then
echo no $outfile is present, exit
return 2
fi

let nsteps=`grep 'LOOP+' $outfile|wc -l`
if [[ -z $nsteps ]]; then return; fi

tagline=`awk '/NSW/ { print NR, $0}' INCAR |sed -e  's|#[ \t]*NSW[ \t]*=[ \t]*[0-9]\+[ ;]*|###|g'|grep NSW|head -1`
if [[ -z $tagline ]]; then 
    echo $tag was not found in $infile, exit
return 3; fi

let line_number=`echo $tagline|awk '{print $1}'`
let nsw=`echo $tagline | sed -e 's/[0-9]\+.*NSW[ \t]*=//' |awk '{print $1}'`
let nsteps_remain=nsw-nsteps
if [[ $nsteps_remain -gt 0  ]]; then
    sed -i "${line_number}s/[ \t]*NSW[ \t]*=[ \t]*[0-9]\+/NSW = $nsteps_remain /" $infile
fi

elif [[ $tag == rseed ]]; then
    rseed=`grep RANDOM_SEED REPORT |tail -1`
    sed -i "\$s/.*/$rseed/" $infile 
else
    echo this tag, $tag, is not supported yet, exit
    return 4
fi

}

# this is default checkpoint function for VASP atomic relaxation and MD jobs
# users can redefine this function as needed in their job scripts
# put any commands that need to run to prepare for the next job here 
ckpt_vasp() {

restarts=`squeue -h -O restartcnt -j $SLURM_JOB_ID`
echo checkpointing the ${restarts}-th job 

#to terminate VASP at the next ionic step 
echo LSTOP = .TRUE. > STOPCAR

#wait until VASP to complete the current ionic step, write out WAVECAR file and quit 
srun_pid=`ps -fle|grep srun|head -1|awk '{print $4}'`
echo wait for srun pid, $srun_pid, to complete 
wait $srun_pid

#save the intermediate results from this job
resdir=${SLURM_JOB_ID}.$restarts
mkdir -p $resdir
cp -p OUTCAR vasprun.xml REPORT XDATCAR OSZICAR $resdir

#prepare inputs for next job 
cp -p CONTCAR POSCAR
update_incar NSW  #update NSW in INCAR with the remaining MD steps 
update_incar rseed
}
