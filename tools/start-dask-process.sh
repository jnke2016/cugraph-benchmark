#!/usr/bin/env bash

export SHARED_DIR=${SHARED_DIR:=/data/benchmark}
WORKER_RMM_POOL_SIZE=${WORKER_RMM_POOL_SIZE:=22G}

########################################
NUMARGS=$#
ARGS=$*
function hasArg {
    (( ${NUMARGS} != 0 )) && (echo " ${ARGS} " | grep -q " $1 ")
}
VALIDARGS="-h --help scheduler workers"
HELP="$0 [<app> ...] [<flag> ...]
 where <app> is:
   scheduler        - start dask scheduler
   workers          - start dask workers
 and <flag> is:
   -h | --help      - print this text

 SHARED_DIR dir is: $SHARED_DIR
"

START_SCHEDULER=0
START_WORKERS=0

if (( ${NUMARGS} == 0 )); then
    echo "${HELP}"
    exit 0
else
    if hasArg -h || hasArg --help; then
	echo "${HELP}"
	exit 0
    fi
    for a in ${ARGS}; do
	if ! (echo " ${VALIDARGS} " | grep -q " ${a} "); then
	    echo "Invalid option: ${a}"
	    exit 1
	fi
    done
fi

if hasArg scheduler; then
    START_SCHEDULER=1
fi
if hasArg workers; then
    START_WORKERS=1
fi

########################################

export DASK_UCX__CUDA_COPY=True
export DASK_UCX__TCP=True
export DASK_UCX__NVLINK=True
export DASK_UCX__INFINIBAND=False
export DASK_UCX__RDMACM=False
export DASK_RMM__POOL_SIZE=0.5GB

#export UCXPY_IFNAME="ibs102"
export UCX_MAX_RNDV_RAILS=1  # <-- must be set in the client env too!
# export DASK_DISTRIBUTED__COMM__TIMEOUTS__CONNECT="100s"
# export DASK_DISTRIBUTED__COMM__TIMEOUTS__TCP="600s"
# export DASK_DISTRIBUTED__COMM__RETRY__DELAY__MIN="1s"
# export DASK_DISTRIBUTED__COMM__RETRY__DELAY__MAX="60s"
# export DASK_DISTRIBUTED__WORKER__MEMORY__Terminate="False"
#export DASK_UCX__REUSE_ENDPOINTS=False
#export UCX_NET_DEVICES=all
#export DASK_UCX_SOCKADDR_TLS_PRIORITY=sockcm
#export DASK_UCX_TLS=rc,sockcm,cuda_ipc,cuda_copy

#export DASK_LOGGING__DISTRIBUTED="DEBUG"

#ulimit -n 100000


SCHEDULER_FILE=${SHARED_DIR}/dask-scheduler.json

SCHEDULER_ARGS="--protocol ucx
                --scheduler-file $SCHEDULER_FILE
               "

WORKER_ARGS="--enable-tcp-over-ucx
             --enable-nvlink
             --disable-infiniband
             --disable-rdmacm
             --rmm-pool-size=$WORKER_RMM_POOL_SIZE
             --local-directory /tmp/$LOGNAME
             --scheduler-file $SCHEDULER_FILE
            "
#             --net-devices=ib0

########################################
scheduler_pid=""
worker_pid=""
num_scheduler_tries=0

function startScheduler {
    python -c 'import dask ; print(f"Using dask from {dask}")' > ${SHARED_DIR}/logs/scheduler.log
    python -m distributed.cli.dask_scheduler $SCHEDULER_ARGS >> ${SHARED_DIR}/logs/scheduler.log 2>&1 &
    scheduler_pid=$!
    echo "scheduler started."
}

if [[ $START_SCHEDULER == 1 ]]; then
    rm -f ${SCHEDULER_FILE}
    mkdir -p ${SHARED_DIR}/logs
    rm -f ${SHARED_DIR}/logs/*

    startScheduler
    num_scheduler_tries=$(python -c "print($num_scheduler_tries+1)")

    # Wait for the scheduler to start first before proceeding, since
    # it may require several retries (if prior run left ports open
    # that need time to close, for example)
    while [ ! -f "$SCHEDULER_FILE" ]; do
        scheduler_alive=$(ps -p $scheduler_pid > /dev/null ; echo $?)
        if [[ $scheduler_alive != 0 ]]; then
            if [[ $num_scheduler_tries != 30 ]]; then
                echo "scheduler failed to start, retry #$num_scheduler_tries"
                startScheduler
                num_scheduler_tries=$(python -c "print($num_scheduler_tries+1)")
            else
                echo "could not start scheduler, exiting."
                exit 1
            fi
        fi
        echo "start-dask-process.sh: waiting for $SCHEDULER_FILE..."
        sleep 6
    done
fi

if [[ $START_WORKERS == 1 ]]; then
    mkdir -p ${SHARED_DIR}/logs
    if [ ! -f "$SCHEDULER_FILE" ]; then
        echo "$SCHEDULER_FILE not present - was the scheduler started first?"
        exit 1
    fi
    python -c 'import dask ; print(f"Using dask from {dask}")' > ${SHARED_DIR}/logs/worker-${HOSTNAME}.log
    python -m dask_cuda.cli.dask_cuda_worker $WORKER_ARGS >> ${SHARED_DIR}/logs/worker-${HOSTNAME}.log 2>&1 &
    worker_pid=$!
    echo "worker(s) started."
fi

# Write out all PIDs started from this script to unique files. This allows for
# easy cleanup by a separate script.
mkdir -p ${SHARED_DIR}/running_pids
WORKER_PID_FILE=${SHARED_DIR}/running_pids/worker--$(uname -n)--${worker_pid}.pid
SCHEDULER_PID_FILE=${SHARED_DIR}/running_pids/scheduler--$(uname -n)--${scheduler_pid}.pid

if [[ $worker_pid != "" ]]; then
    echo $worker_pid > $WORKER_PID_FILE
fi
if [[ $scheduler_pid != "" ]]; then
    echo $scheduler_pid > $SCHEDULER_PID_FILE
fi

# Make the script wait until all background processes it started are
# complete. This allows for scripts that call this script to know when those
# jobs complete when this script is not run in the background.
if [[ $worker_pid != "" ]]; then
    echo "waiting for worker pid $worker_pid..."
    wait $worker_pid
    rm -f $WORKER_PID_FILE
fi
if [[ $scheduler_pid != "" ]]; then
    echo "waiting for scheduler pid $scheduler_pid..."
    wait $scheduler_pid
    rm -f $SCHEDULER_PID_FILE
fi
