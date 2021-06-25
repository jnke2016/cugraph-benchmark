#!/usr/bin/env bash

export SHARED_DIR=${SHARED_DIR:=/gpfs/fs1/projects/sw_rapids/users/adattagupta}
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

#echo ${SCHEDULER_ARGS}
if [[ $START_SCHEDULER == 1 ]]; then
    rm -f ${SCHEDULER_FILE}
    mkdir -p ${SHARED_DIR}/logs
    rm -f ${SHARED_DIR}/logs/*
    if [[ $START_WORKERS == 1 ]]; then
        python -m distributed.cli.dask_scheduler $SCHEDULER_ARGS > ${SHARED_DIR}/logs/scheduler.log 2>&1 &
        while [ ! -f "$SCHEDULER_FILE" ]; do
            echo "waiting for ${SCHEDULER_FILE}..."
            sleep 6
	done
	echo "scheduler started."
    else
	python -m distributed.cli.dask_scheduler $SCHEDULER_ARGS > ${SHARED_DIR}/logs/scheduler.log 2>&1 &
    fi
fi

if [[ $START_WORKERS == 1 ]]; then
    mkdir -p ${SHARED_DIR}/logs
    while [ ! -f "$SCHEDULER_FILE" ]; do
            echo "$SCHEDULER_FILE not present - was the scheduler started first?"
            sleep 6
    done
    python -m dask_cuda.cli.dask_cuda_worker $WORKER_ARGS > ${SHARED_DIR}/logs/worker-${HOSTNAME}.log 2>&1 &
fi
