# cugraph-benchmark

cuGraph benchmarking scripts.

## High-level steps:
1. Create an environment containing the version of cuGraph and all required dependencies.  Use `tools/create-conda-env.sh`.
2. Run the benchmark scripts.  Use `python nightly/main.py --help` for details.


### Creating a conda environment
The environment used for benchmarking cugraph can be built in any way that works for the user running the benchmarks. The only requirement is that `cugraph` can be imported and run from python.  Conda environments are an obvious choice, so the following script has been provided to create a conda env for benchmarks.  Note that the conda env creation step only needs to be done after a cugraph code change, or a cugraph dependency changes.

On a machine with the correct compiler support and CUDA tools, run the following script:
```
./tools/create-conda-env.sh  # Creates a conda env by building cugraph and specific dependencies from source
```

### Running benchmark scripts
#### For single-node multi-GPU runs:
* expose the desired GPUs to the benchmark run via `CUDA_VISIBLE_DEVICES`
* run the benchmark script, below is an example:
```
python nightly/main.py --scale=23 --algo=bfs
```
Use `--help` for a list of all available benchmark options.

#### For multi-node multi-GPU (MNMG) runs:
Multi-node runs assume a NFS mount or other shared file mechanism is in place so the generated dask scheduler file can be accessed by dask workers on other nodes. For the purposes of these examples, it will be assumed that an NFS mount is available.  The examples also assume the conda env is named `cugraph_bench`, since that is the default name used by the `tools/create-conda-env.sh` script.

* start the dask scheduler and the workers on a node:
```
node1$ conda activate cugraph_bench
(cugraph_bench) node1$ export SHARED_DIR=/some/nfs/dir              # This must be set!
(cugraph_bench) node1$ export WORKER_RMM_POOL_SIZE=12G              # Make larger if possible
(cugraph_bench) node1$ export CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7  # Ensure all 8 GPUs are available
(cugraph_bench) node1$ cd /path/to/cugraph-benchmark
(cugraph_bench) node1$ ./tools/start-dask-process.sh scheduler workers
```

* start additional workers on other nodes:
```
node2$ conda activate cugraph_bench
(cugraph_bench) node2$ export SHARED_DIR=/some/nfs/dir              # This must be set!
(cugraph_bench) node2$ export WORKER_RMM_POOL_SIZE=12G              # Make larger if possible
(cugraph_bench) node2$ export CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7  # Ensure all 8 GPUs are available
(cugraph_bench) node2$ cd /path/to/cugraph-benchmark
(cugraph_bench) node2$ ./tools/start-dask-process.sh workers
```

* run the benchmarks, see `--help` for specific options:
```
node3$ conda activate cugraph_bench
(cugraph_bench) node3$ export SHARED_DIR=/some/nfs/dir
(cugraph_bench) node3$ export UCX_MAX_RNDV_RAILS=1                  # This must be set!
(cugraph_bench) node3$ cd /path/to/cugraph-benchmark
(cugraph_bench) node3$ python nightly/main.py --scale=23 --algo=pagerank --unweighted --dask-scheduler-file=$SHARED_DIR/dask-scheduler.json
```
_Note: the benchmark run above may be able to be run on `node1` or `node2` above._

#### Other notes for MNMG runs:
* The scripts currently assume the InfiniBand interface is `ib0`. Change `tools/start-dask-process.sh` accordingly if `ib0` is not correct for your system.
* Certain error conditions (eg. OOM) _may_ require that the workers (and possibly scheduler) are restarted.
* Use `nvidia-smi` on the nodes to confirm that worker processes are/are not running.
