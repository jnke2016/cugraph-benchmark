# Copyright (c) 2021, NVIDIA CORPORATION.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import sys

from cugraph.dask.common.mg_utils import get_visible_devices

# Do this so the benchmark tools don't have to be installed
from pathlib import Path
_tools_lib_dir = Path(__file__).absolute().parent.parent / "tools" / "python"
sys.path.append(str(_tools_lib_dir))

from benchmark.reporting import (generate_console_report,
                                 update_csv_report,
                                 generate_result_report,
                                )

import cugraph_funcs
import cugraph_dask_funcs
from benchmark_run import BenchmarkRun


def log(s, end="\n"):
    print(s, end=end)
    sys.stdout.flush()


def run(algos,
        scale=None,
        csv_graph_file=None,
        orc_dir=None,
        csv_results_file=None,
        unweighted=False,
        symmetric=False,
        edgefactor=None,
        dask_scheduler_file=None,
        report_dir=None,
        num_gpus_used=0):
    """
    Run the nightly benchmark on cugraph.
    Return True on success, False on failure.
    """
    seed = 42
    n_gpus = num_gpus_used or len(get_visible_devices())
    if (dask_scheduler_file is None) and (n_gpus < 2):
        funcs = cugraph_funcs
    else:
        funcs = cugraph_dask_funcs

    # Setup the benchmarks to run based on algos specified, or all.
    # Values are either callables, or tuples of (callable, args) pairs.
    benchmarks = {"bfs": funcs.bfs,
                  "sssp": funcs.sssp,
                  "louvain": funcs.louvain,
                  "pagerank": funcs.pagerank,
                  "wcc": funcs.wcc,
                  "katz": funcs.katz,
                 }

    if algos:
        invalid_benchmarks = set(algos) - set(benchmarks.keys())
        if invalid_benchmarks:
            raise ValueError("Invalid benchmark(s) specified "
                             f"{invalid_benchmarks}")
        benchmarks_to_run = [benchmarks[b] for b in algos]
    else:
        benchmarks_to_run = []

    # Call the global setup. This is used for setting up Dask, initializing
    # output files/reports, etc.
    log("calling setup...", end="")
    setup_objs = funcs.setup(dask_scheduler_file)
    log("done.")

    ignore_weights = False

    try:
        if csv_graph_file:
            log("running read_csv...", end="")
            df = funcs.read_csv(csv_graph_file, 0)
            log("done.")
        elif scale:
            log("running generate_edgelist (RMAT)...", end="")
            df = funcs.generate_edgelist(scale,
                                         edgefactor=edgefactor,
                                         seed=seed,
                                         unweighted=unweighted)
            log("done.")
        elif orc_dir:
            log(f"reading ORC files from {orc_dir}...", end="")
            df = funcs.read_orc_dir(orc_dir)
            log("done.")
            ignore_weights = True
        else:
            raise ValueError("Must specify scale, csv_graph_file, or orc_dir")

        benchmark = BenchmarkRun(df,
                                 (funcs.construct_graph, (symmetric,ignore_weights)),
                                 benchmarks_to_run,
                                )
        success = benchmark.run()

        # Report results
        print(generate_console_report(benchmark.results))

        if report_dir:
            generate_result_report(report_dir, benchmark.results, n_gpus,
                                   scale, edgefactor, orc_dir)

        if csv_results_file:
            update_csv_report(csv_results_file, benchmark.results, n_gpus)

    except:
        success = False
        raise

    finally:
        # Global cleanup
        log("calling teardown...", end="")
        funcs.teardown(*setup_objs)
        log("done.")

    return success is True


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", type=int, default=None,
                    help="scale factor for the graph edgelist generator "
                    "(num_verts=2**SCALE).")
    ap.add_argument("--csv", type=str, default=None,
                    help="path to CSV file to read instead of generating a "
                    "graph edgelist.")
    ap.add_argument("--orc-dir", type=str, default=None,
                    help="directory containing ORC files to read as input.")
    ap.add_argument("--unweighted", default=False, action="store_true",
                    help="Generate a graph without weights.")
    ap.add_argument("--algo", action="append",
                    help="Algo to benchmark. May be specified multiple times. "
                    "Default is all algos.")
    ap.add_argument("--dask-scheduler-file", type=str, default=None,
                    help="Dask scheduler file for multi-node configuration.")
    ap.add_argument("--symmetric-graph", default=False, action="store_true",
                    help="Generate a symmetric (undirected) Graph instead of "
                    "a DiGraph.")
    ap.add_argument("--edgefactor", type=int, default=16,
                    help="edge factor for the graph edgelist generator "
                    "(num_edges=num_verts*EDGEFACTOR).")
    ap.add_argument("--report-output-dir", type=str, default=None,
                    help="the directory the <algo>_benchmark_results.txt file "
                    "should be written to.")
    ap.add_argument("--num-gpus-used", type=int, default=0,
                    help="the expected number of GPUs to be used.")
    args = ap.parse_args()

    if [args.scale, args.csv, args.orc_dir].count(None) != 2:
        exitcode = 1
        log("one and only one of --scale, --csv, or --orc-dir must be "
            "specified.")
    else:
        exitcode = run(algos=args.algo,
                       scale=args.scale,
                       csv_graph_file=args.csv,
                       orc_dir=args.orc_dir,
                       csv_results_file="out.csv",
                       unweighted=args.unweighted,
                       symmetric=args.symmetric_graph,
                       edgefactor=args.edgefactor,
                       dask_scheduler_file=args.dask_scheduler_file,
                       report_dir=args.report_dir,
                       num_gpus_used=args.num_gpus_used)

    sys.exit(exitcode)
