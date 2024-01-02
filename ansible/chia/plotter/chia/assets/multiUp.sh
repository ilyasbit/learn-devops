#!/usr/bin/env bash

#!/bin/env bash
source ~/.bashrc

while [[ "$(which chia)" == "" ]]; do
  . /opt/chia-blockchain/activate
done

source /root/.worker/env

baseUrl=$BASEURL
apiKey=$APIKEY
chunkPath=/mount_chunk
realPath=/chunk
plotsDir=/plots
chia plots add -d ${chunkPath}

plotFile=$1

plotDetail=$(rclone lsjson ${chunkPath}/${plotFile})
plotName=$(echo $plotDetail | jq -r '.[0].Name')
declare -i plotSize=$(echo $plotDetail | jq -r '.[0].Size')

chunkDetail=$(rclone lsjson ${realPath} --include "${plotName}.rclone_chunk*")
chunkHead=$(rclone lsjson ${realPath}/${plotName} | jq -r '.[].Name')
chunkCount=$(echo $chunkDetail | jq length)

chunk001=$(echo $chunkDetail | jq -r '.[] | select(.Name | endswith("rclone_chunk.001")) | .Name')
chunk002=$(echo $chunkDetail | jq -r '.[] | select(.Name | endswith("rclone_chunk.002")) | .Name')
chunk003=$(echo $chunkDetail | jq -r '.[] | select(.Name | endswith("rclone_chunk.003")) | .Name')
chunk004=$(echo $chunkDetail | jq -r '.[] | select(.Name | endswith("rclone_chunk.004")) | .Name')
chunk005=$(echo $chunkDetail | jq -r '.[] | select(.Name | endswith("rclone_chunk.005")) | .Name')

chunkHeadSize=$(rclone lsjson ${realPath}/${plotName} | jq -r '.[].Size')
chunk001Size=$(echo $chunkDetail | jq -r --arg chunk01 "$chunk001" '.[] | select(.Name == $chunk01) | .Size')
chunk002Size=$(echo $chunkDetail | jq -r --arg chunk02 "$chunk002" '.[] | select(.Name == $chunk02) | .Size')
chunk003Size=$(echo $chunkDetail | jq -r --arg chunk03 "$chunk003" '.[] | select(.Name == $chunk03) | .Size')
chunk004Size=$(echo $chunkDetail | jq -r --arg chunk04 "$chunk004" '.[] | select(.Name == $chunk04) | .Size')
chunk005Size=$(echo $chunkDetail | jq -r --arg chunk05 "$chunk005" '.[] | select(.Name == $chunk05) | .Size')
totalChunkSize=$(($chunk001Size + $chunk002Size + $chunk003Size + $chunk004Size + $chunk005Size))
