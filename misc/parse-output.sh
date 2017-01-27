#!/bin/bash
# Parse the output from run-experiment.sh

FN=$1
NROOTS=64
if [ -z "$FN" ]; then
	echo "usage: parse-output.sh <output_file>"
	exit 2
fi

# Graph500
echo -n 'Graph500,BFS,graph construction,'
echo $(grep "construction_time" "$FN" | awk '{print $2}') 
echo -n 'Graph500,BFS,graph generation,'
echo $(grep "generation_time" "$FN" | awk '{print $2}')
echo -n 'Graph500,BFS,Time,'
grep "mean_time" "$FN" | awk '{print $2}'

# GraphBIG
echo -n 'GraphBIG,BFS,File reading,'
grep -A 7 "Benchmark: BFS" "$FN" | awk -v T=0 '/time/{if(T%2==0){print $3} T++}' | awk '{s+=$1}END{print s/NR}'
grep -A 7 "Benchmark: BFS" "$FN" | awk -v T=1 '/time/{if(T%2==0){print "GraphBIG,BFS,Time," $3} T++}'
echo -n 'GraphBIG,SSSP,File reading,'
grep -A 7 'Benchmark: sssp' "$FN" | awk -v T=0 '/time/{if(T%2==0){print $3} T++}' | awk '{s+=$1}END{print s/NR}'
grep -A 7 'Benchmark: sssp' "$FN" | awk -v T=1 '/time/{if(T%2==0){print "GraphBIG,SSSP,Time," $3} T++}'
# XXX: PageRank only does one trial
echo -n 'GraphBIG,PageRank,File reading,'
grep -A 7 "Degree Centrality" "$FN" | awk -v T=0 '/time/{if(T%2==0){print $3} T++}' | awk '{s+=$1}END{print s/NR}'
grep 'iteration #' "$FN" | awk '{print "GraphBIG,PageRank,Iterations," $4}'
grep -A 11 "Degree Centrality" "$FN" | awk -v T=1 '/time/{if(T%2==0){print "GraphBIG,PageRank,Time," $3} T++}'

# GraphMat
echo -n 'GraphMat,BFS,File reading,'
grep -A 4 'BFS root:' "$FN" | awk -F ':' '/, time/{print $2}' | awk '{s+=$1}END{print s/NR}'
# The time to build, sort, allocate the data structure
# XXX: This surprisingly takes between 0.7-2.9 seconds. Why the discrepancy?
grep -A 17 'BFS root:' "$FN" | awk '/A from memory/{print "GraphMat,BFS,Data structure build," $(NF-1)}'
# The time to build, sort, allocate the data structure.
grep -A 20 'BFS root:' "$FN" | awk '/Time/{print "GraphMat,BFS,Time," ($3/1000)}'
echo -n 'GraphMat,SSSP,File reading,'
grep -A 4 'SSSP root:' "$FN" | awk -F ':' '/, time/{print $2}' | awk '{s+=$1}END{print s/NR}'
grep -A 17 'SSSP root:' "$FN" | awk '/A from memory/{print "GraphMat,SSSP,Data structure build," $(NF-1)}'
grep -A 20 'SSSP root:' "$FN" | awk '/Time/{print "GraphMat,SSSP,Time," ($3/1000)}'
# XXX: GraphMat PageRank goes for 149 iterations, also only runs one trial.
echo -n 'GraphMat,PageRank,File reading,'
grep -B 18 "PR Time" "$FN" | awk -F ':' '/, time/{print $2}' | awk '{s+=$1}END{print s/NR}'
grep -B 5 "PR Time" "$FN" | awk '/A from memory/{print "GraphMat,PageRank,Data structure build," $(NF-1)}'
grep -B 1 "PR Time" "$FN" | awk '/Completed/{print "GraphMat,PageRank,Iterations," $2}'
awk '/PR Time/{print "GraphMat,PageRank,Time," ($4/1000)}' "$FN"

# GAP
# The first 64 are BFS, the next 64 SSSP, the last 1 PageRank.
echo -n 'GAP,BFS,File reading,'
awk '/Read Time:/{i++; if(i<=64)print $3}' "$FN" | awk '{s+=$1}END{print s/NR}'
awk '/Build Time:/{i++; if(i<=64)print "GAP,BFS,Data structure build," $3}' "$FN"
awk '/Average Time:/{i++; if(i<=64)print "GAP,BFS,Time," $3}' "$FN"
echo -n 'GAP,SSSP,File reading,'
awk '/Read Time:/{i++; if(i>64 && i<=128)print $3}' "$FN" | awk '{s+=$1}END{print s/NR}'
awk '/Build Time:/{i++; if(i>64 && i<=128)print "GAP,SSSP,Data structure build," $3}' "$FN"
awk '/Average Time:/{i++; if(i>64 && i<=128)print "GAP,SSSP,Time," $3}' "$FN"
echo -n 'GAP,PageRank,File reading,'
awk '/Read Time:/{i++; if(i>128)print $3}' "$FN" | awk '{s+=$1}END{print s/NR}'
awk '/Build Time:/{i++; if(i>128)print "GAP,PageRank,Data structure build," $3}' "$FN"
grep -B 2 'Average Time:' "$FN" | awk '/^\s*[0-9]+/{print "GAP,PageRank,Iterations," $1}'
awk '/Average Time:/{i++; if(i>128)print "GAP,PageRank,Time," $3}' "$FN"

