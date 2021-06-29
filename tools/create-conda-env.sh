#!/usr/bin/env bash

# Creates a conda environment to be used for cugraph benchmarking.

# Abort script on first error
set -e

THIS_SCRIPT_DIR=${BASH_SOURCE%/*}
NUMARGS=$#
ARGS=$*
function hasArg {
    (( ${NUMARGS} != 0 )) && (echo " ${ARGS} " | grep -q " $1 ")
}
VALIDARGS="--from-source -h --help"
HELP="$0 [<flag> ...]
 where <flag> is:
   --from-source          - build cugraph, UCX and other packages from source. This involves cloning from the
                            respective repos, installing a full build toolchain in the conda env, applying
                            patches, etc. Without this option, a conda env is created only from pre-built
                            conda packages downloaded from anaconda.org channels.
   --cugraph-from-source  - only build cugraph from source, all other packages are installed from conda.
   -h | --help            - print this text
"

# Set the CONDA_ENV env var to the desired name of the new conda
# env. This defaults to "cugraph_bench" if unset.
CONDA_ENV=${CONDA_ENV:=cugraph_bench}
CUGRAPH_REPO_URL="https://github.com/rapidsai/cugraph.git --branch=branch-21.08"
DASK_REPO_URL=https://github.com/dask/dask
DASK_DISTRIBUTED_REPO_URL=https://github.com/dask/distributed
#DASK_CUDA_REPO_URL="https://github.com/rapidsai/dask-cuda --branch=branch-21.08"
UCX_REPO_URL=https://github.com/openucx/ucx.git
#UCX_REPO_URL="https://github.com/openucx/ucx --branch=v1.9.x"
#UCX_PY_REPO_URL=https://github.com/rapidsai/ucx-py.git
BUILD_DIR=$(cd $(dirname $THIS_SCRIPT_DIR) ; pwd)/build
DATE=$(date -u "+%Y%m%d%H%M%S")_UTC
ENV_EXPORT_FILE=${BUILD_DIR}/$(basename ${CONDA_ENV})-${DATE}.txt

ALL_FROM_SOURCE=0
CUGRAPH_FROM_SOURCE=0

# CONDA_ENV can be a name or a path. Using a path is useful for creating a conda
# env in an alternate location (home dir, NFS dir, etc.)
if echo $CONDA_ENV|grep -q "^/"; then
    CONDA_NAME_OPTION="-p $CONDA_ENV"
else
    CONDA_NAME_OPTION="-n $CONDA_ENV"
fi

if hasArg -h || hasArg --help; then
    echo "${HELP}"
	exit 0
fi
if hasArg --from-source; then
    ALL_FROM_SOURCE=1
fi
if hasArg --cugraph-from-source; then
    CUGRAPH_FROM_SOURCE=1
fi

function cloneRepo {
   repo_url=$1
   repo_name=$2
   mkdir -p $BUILD_DIR
   pushd $BUILD_DIR
   echo "Clone $repo_url in $BUILD_DIR..."
   if [ -d $repo_name ]; then
      rm -rf $repo_name
      if [ -d $repo_name ]; then
         echo "ERROR: ${BUILD_DIR}/$repo_name was not completely removed."
         error 1
      fi
   fi
   git clone $repo_url
   popd
}

################################################################################
# All options result in removing the existing env of the same name
echo "removing old $CONDA_ENV env..."
echo $(conda env remove -y $CONDA_NAME_OPTION)

################################################################################
# Create a conda env from nightly packages
if [[ $ALL_FROM_SOURCE == 0 ]] && [[ $CUGRAPH_FROM_SOURCE == 0 ]]; then
    conda create -y \
          $CONDA_NAME_OPTION \
          -c rapidsai-nightly \
          -c rapidsai \
          -c nvidia \
          -c conda-forge \
          cugraph \
          python=3.8 \
          cudatoolkit=11.0

################################################################################
# Create a conda env from-source: either cugraph only, or cugraph + deps built
# from source.
else
    cloneRepo "$CUGRAPH_REPO_URL" cugraph
    conda create -y $CONDA_NAME_OPTION python=3.8
    eval "$(conda shell.bash hook)"
    conda activate $CONDA_ENV
    conda env update $CONDA_NAME_OPTION --file ${BUILD_DIR}/cugraph/conda/environments/cugraph_dev_cuda11.0.yml

    if [[ $ALL_FROM_SOURCE == 1 ]]; then
        # Clone repos
        cloneRepo "$DASK_REPO_URL" dask
        cloneRepo "$DASK_DISTRIBUTED_REPO_URL" distributed
        #cloneRepo "$DASK_CUDA_REPO_URL" dask-cuda
        cloneRepo "$UCX_REPO_URL" ucx
        #cloneRepo "$UCX_PY_REPO_URL" ucx-py

        echo "Installing additional packages for building dependencies..."
        conda install -y \
              -c gpuci \
              -c rapidsai-nightly \
              -c rapidsai \
              -c nvidia \
              -c conda-forge \
              -c defaults \
              "setuptools=49.6.0" \
              cmake \
              automake \
              make \
              libtool

        # Remove packages that are present from the dev environment that will
        # be replaced by from-source build/installs
        conda remove -y --force dask dask-core distributed ucx ucx-proc

        # Build UCX
        echo "Building UCX..."
        cd ${BUILD_DIR}/ucx
        # 1.9
        #curl -LO https://raw.githubusercontent.com/rapidsai/ucx-split-feedstock/11ad7a3c1f25514df8064930f69c310be4fd55dc/recipe/cuda-alloc-rcache.patch
        #git apply cuda-alloc-rcache.patch
        #./autogen.sh
        #mkdir -p build
        #cd build
        #../contrib/configure-release \
        #    --enable-mt \
        #    --with-rdmacm \
        #    --with-verbs \
        #    --prefix=$CONDA_PREFIX \
        #    --with-cuda=$CUDA_HOME
        #CPPFLAGS="-I/$CUDA_HOME/include"
        #make -j install
        # 1.11
        ./autogen.sh
        mkdir -p build
        cd build
        ../contrib/configure-release \
            --prefix=$CONDA_PREFIX \
            --with-cuda=$CUDA_HOME \
            --enable-mt CPPFLAGS="-I/$CUDA_HOME/include"
        make -j install

        # Build UCX-Py
        #echo "Building UCX-Py..."
        #cd ${BUILD_DIR}/ucx-py
        #python -m pip install .

        # Build Dask
        echo "Building Dask..."
        cd ${BUILD_DIR}/dask
        python -m pip install .

        # Build Distributed
        echo "Building Distributed..."
        cd ${BUILD_DIR}/distributed
        python -m pip install .

        # Build Dask-CUDA
        #echo "Building Dask-CUDA..."
        #cd ${BUILD_DIR}/dask-cuda
        #python -m pip install .
    fi

    # Build cugraph
    echo "Building cuGraph..."
    cd ${BUILD_DIR}/cugraph
    ./build.sh uninstall clean libcugraph cugraph
fi

echo "Created conda env $CONDA_ENV"

# Dump the contents of the new enviornment if it needs to be recreated with
# exact package versions at a later time.
mkdir -p $BUILD_DIR
conda list $CONDA_NAME_OPTION --export > $ENV_EXPORT_FILE
echo "Created $ENV_EXPORT_FILE , use \"conda create --name $CONDA_ENV --file $ENV_EXPORT_FILE\" to recreate $CONDA_ENV with exact versions."
