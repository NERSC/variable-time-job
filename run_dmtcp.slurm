#!/bin/bash 

#SBATCH -q regular 
#SBATCH -N 1
#SBATCH -C haswell 
#SBATCH -J test_dmtcp 
#SBATCH -t 48:00:00
#SBATCH -e %x-%j.err
#SBATCH -o %x-%j.out
#SBATCH --time-min=02:00:00
#
#SBATCH --comment=14-00:00:00
#SBATCH --signal=B:USR1@300
#SBATCH --requeue
#SBATCH --open-mode=append

#OpenMP settings:
export OMP_NUM_THREADS=64
export OMP_PLACES=threads
export OMP_PROC_BIND=true

module load dmtcp nersc_cr

#checkpointing once every hour
start_coordinator -i 1800

#c/r jobs
if [[ $(restart_count) == 0 ]]; then
    dmtcp_launch -j ./a.out &
elif [[ $(restart_count)>0 ]] && [[ -e dmtcp_restart_script.sh ]]; then
    ./dmtcp_restart_script.sh &
else
    echo "Failed to restart the job, exit"; exit
fi

# requeueing the job if remaining time >0
ckpt_command=ckpt_dmtcp #additional checkpointing right before the job hits the walllimit
requeue_job func_trap USR1
wait
