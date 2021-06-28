import os
import sys
import time
import yaml

from dask.distributed import Client
from dask_cuda.initialize import initialize


expected_workers = int(sys.argv[1])
if expected_workers is None:
    expected_workers = os.environ.get("NUM_WORKERS", 16)


# use scheduler file path from global environment if none
# supplied in configuration yaml
scheduler_file_path = sys.argv[2]
if scheduler_file_path is None:
    scheduler_file_path = os.environ.get("SCHEDULER_FILE")

os.environ["UCX_MAX_RNDV_RAILS"] = "1"

initialize(
    enable_tcp_over_ucx=True,
    enable_nvlink=True,
    enable_infiniband=False,
    enable_rdmacm=False,
)

ready = False
while not ready:
    with Client(scheduler_file=scheduler_file_path) as client:
        workers = client.scheduler_info()['workers']
        if len(workers) < expected_workers:
            print(f'Expected {expected_workers} but got {len(workers)}, waiting..')
            time.sleep(10)
        else:
            print(f'Got all {len(workers)} workers')
            ready = True
