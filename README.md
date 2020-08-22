# variable-time-job

This project is to keep track of the variable-time-job scripts, which automates the job preemption and restart from user space.

Variable-time-job scripts create better backfill opportunities on the system by splitting long running jobs into multiple shorter ones, 
therefore improve system utilizations and queue turnaround for long running jobs.
With variable-time-job scripts users can run jobs with any length, e.g., weeks, on Cori where the maximum timelimit imposed by the batch system 
is 48 hours.  
 
Variable-time-job scripts consist of a slurm job script generator and a set of bash functions that implement the job preemption and restart.   
To use the variable-time job scripts, applications must be able to checkpoint either by themselves internally 
or by external checkpoint tools like [DMTCP](http://dmtcp.sourceforge.net/). 

The original scripts were developed by [Tiffany Connors](mailto:tconnors@lbl.gov) and [Rebecca Hartman-Baker](mailto:csamuel@lbl.gov) in the summer of 2017,
and are currently maintained by [Zhengji Zhao](mailto:zzhao@lbl.gov), who added more functions to support VASP
and other applications that use DMTCP to checkpoint. 
 
