#!/bin/bash
# Download and build all the required graph processing libraries
USAGE="usage: run-experiment.sh <libdir>
	<libdir> repositories directory. Default: ./lib"

LIBDIR="$(pwd)/lib"
if [ -n "$1" ]; then
	LIBDIR="$1"
fi
echo "Installing into $LIBDIR ..."

mkdir -p "$LIBDIR"
cd "$LIBDIR"
# GAP:
git clone https://github.com/sampollard/gapbs.git
cd gapbs; make

# GraphBIG:
cd "$LIBDIR"
git clone https://github.com/sampollard/graphBIG.git
cd graphBIG; make
cd GraphBIG/benchmark
make clean all

# GraphMat:
cd "$LIBDIR"
module load intel/17
git clone https://github.com/sampollard/GraphMat.git
cd GraphMat; make

# Graph500:
cd "$LIBDIR"
git clone https://github.com/sampollard/graph500.git
cd graph500
echo "Building assuming you have gcc with OpenMP support."
cp make-incs/make.inc-gcc make.inc
ex -s make.inc "+:%s/gcc-4.6/gcc/g" "+:%s/# BUILD_OPENMP/BUILD_OPENMP/g" "+:%s/# CFLAGS_OPENMP/CFLAGS_OPENMP/g"  '+:x'
make

# PowerGraph:
# NOTE: Shared memory only!
cd "$LIBDIR"
NUM_CORES=$(grep -c ^processor /proc/cpuinfo)
if [ "$NUM_CORES" -gt 64 ]; then
    export GRAPHLAB_THREADS_PER_WORKER=64
else
    export GRAPHLAB_THREADS_PER_WORKER=$NUM_CORES
fi
git clone https://github.com/sampollard/PowerGraph
cd PowerGraph
./configure --no_jvm
cd release/toolkits/graph_analytics
make -j4
cd "$LIBDIR"
