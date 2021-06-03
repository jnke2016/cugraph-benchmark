#!/usr/bin/env bash

# Creates a conda environment to be used for cugraph benchmarking.

# Abort script on first error
set -e

THIS_SCRIPT_DIR=${BASH_SOURCE%/*}

# Set the CONDA_ENV env var to the desired name of the new conda
# env. This defaults to "cugraph_bench" if unset.
CONDA_ENV=${CONDA_ENV:=cugraph_bench}
CUGRAPH_REPO_URL=https://github.com/rapidsai/cugraph.git
DASK_REPO_URL=https://github.com/dask/dask
DASK_DISTRIBUTED_REPO_URL=https://github.com/dask/distributed
DASK_CUDA_REPO_URL=https://github.com/rapidsai/dask-cuda
UCX_REPO_URL=https://github.com/openucx/ucx.git
#UCX_REPO_URL="https://github.com/openucx/ucx --branch v1.9.x"
UCX_PY_REPO_URL=https://github.com/rapidsai/ucx-py.git
BUILD_DIR=$(cd $(dirname $THIS_SCRIPT_DIR) ; pwd)/build

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

########################################

echo "removing old $CONDA_ENV env..."
echo $(conda env remove -y --name $CONDA_ENV)

# Clone repos
cloneRepo $CUGRAPH_REPO_URL cugraph
cloneRepo $DASK_REPO_URL dask
cloneRepo $DASK_DISTRIBUTED_REPO_URL distributed
cloneRepo $DASK_CUDA_REPO_URL dask-cuda
cloneRepo $UCX_REPO_URL ucx
cloneRepo $UCX_PY_REPO_URL ucx-py

# Create the new conda env, starting with the build tools
conda create -y --name $CONDA_ENV python=3.8
eval "$(conda shell.bash hook)"
conda activate $CONDA_ENV
conda env update -n $CONDA_ENV --file ${BUILD_DIR}/cugraph/conda/environments/cugraph_dev_cuda11.0.yml

echo "Installing additional packages..."
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

# Install patched NCCL, needed for DGX1 (should not cause problems on
# DGX2 or elsewhere)
conda remove -y -n $CONDA_ENV --force nccl
#conda install -y -n $CONDA_ENV -c nvidia/label/disable-nvb nvidia/label/disable-nvb::nccl=2.9.6.1
conda install -y -n $CONDA_ENV -c conda-forge nccl=2.9.9

# Remove packages that are present from the dev environment that will
# be replaced by from-source build/installs
conda remove -y --force dask dask-core dask-cuda distributed ucx ucx-proc ucx-py

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

# Build cugraph
echo "Building cuGraph..."
cd ${BUILD_DIR}/cugraph
./build.sh uninstall clean libcugraph cugraph

# Build UCX-Py
echo "Building UCX-Py..."
cd ${BUILD_DIR}/ucx-py
python -m pip install .

# Build Dask
echo "Building Dask..."
cd ${BUILD_DIR}/dask
python -m pip install .

# Build Distributed
echo "Building Distributed..."
cd ${BUILD_DIR}/distributed
python -m pip install .

# Build Dask-CUDA
echo "Building Dask-CUDA..."
cd ${BUILD_DIR}/dask-cuda
python -m pip install .
