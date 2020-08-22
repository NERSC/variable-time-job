#!/bin/bash
#SBATCH -J md 
#SBATCH -N 2 
#SBATCH -C knl
#SBATCH -q flex 
#SBATCH -t 48:00:00
#SBATCH --time-min=02:00:00 
#SBATCH --error=%x-%j.err
#SBATCH --output=%x-%j.out

#
#SBATCH --comment=336:00:00 
#SBATCH --signal=B:USR1@300 
#SBATCH --requeue 
#SBATCH --open-mode=append 

module load vasp/20181030-knl
export OMP_NUM_THREADS=4

# launching 1 task every 4 cores (16 CPUs)
srun -n32 -c16 --cpu_bind=cores vasp_std  &


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

ckpt_command=ckpt_vasp 

# requeueing the job if remaining time >0 
. /usr/common/software/variable-time-job/setup.sh 
requeue_job func_trap USR1 

wait

