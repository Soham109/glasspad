#!/bin/sh
# Contact sheet: scripts/sheet.sh out.png cols w h img1 img2 ...
out=$1; cols=$2; w=$3; h=$4; shift 4
n=$#; rows=$(( (n + cols - 1) / cols ))
args=""; i=0; fl=""
for f in "$@"; do args="$args -i $f"; fl="$fl[$i:v]scale=$w:$h[v$i];"; i=$((i+1)); done
lay=""; i=0
while [ $i -lt $n ]; do c=$((i % cols)); r=$((i / cols)); lay="$lay${lay:+|}$((c*w))_$((r*h))"; i=$((i+1)); done
ins=""; i=0; while [ $i -lt $n ]; do ins="$ins[v$i]"; i=$((i+1)); done
ffmpeg -loglevel error -y $args -filter_complex "${fl}${ins}xstack=inputs=$n:layout=$lay:fill=white" -frames:v 1 "$out"
