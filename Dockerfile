ARG FROM_IMAGE=gpuci/miniconda-cuda
ARG CUDA_VER=11.0
ARG LINUX_VER=ubuntu20.04

FROM ${FROM_IMAGE}:${CUDA_VER}-devel-${LINUX_VER}

COPY nightly /cugraph-benchmark/nightly
COPY tools /cugraph-benchmark/tools

ENV CUDA_HOME=/usr/local/cuda

RUN apt-get update -y \
 && apt-get install -y pkg-config \
 && cd /cugraph-benchmark \
 && ./tools/create-conda-env.sh
