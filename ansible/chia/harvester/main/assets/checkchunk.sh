#!/bin/env bash

source ~/.worker/env

baseUrl=$BASEURL
apiKey=$APIKEY

umount -l /storj-bucket/*
rm -rf /storj-bucket/*

while [[ "$(which chia)" != "/opt/chia-blockchain/venv/bin/chia" ]]; do
  . /opt/chia-blockchain/activate
done

function submitUpdate() {
  chunkId=$1
  status=$2
  curl -s -X POST "${baseUrl}/chunk/updateChunkStatus?chunkId=${chunkId}&apiKey=${apiKey}&status=$status" >/dev/null
}

function clearUp() {
  chunkDetail=$1
  chunkId=$(echo $chunkDetail | jq -r '.id')
  plotName=$(echo $chunkDetail | jq -r '.plotName')
  umount -l /storj-bucket/${chunkId}
  umount -l /storj-bucket/*
  #wait until umount success
  while true; do
    if [[ "$(mount | grep /storj-bucket/${chunkId} | wc -l)" -eq 0 ]]; then
      break
    fi
    sleep 3
  done
  rm -rf /storj-bucket/${chunkId}
  #rm -rf /tmp/${chunkId}.*
  #rm -rf /tmp/${plotName}.*
}

function mountChunk() {
  chunkDetail=$1
  chunkId=$(echo $chunkDetail | jq -r '.id')
  chunkConfig=$(echo $chunkDetail | jq '.config')
  touch /tmp/${chunkId}.conf
  echo -e $chunkConfig >/tmp/${chunkId}.conf
  sed -i 's/"//g' /tmp/${chunkId}.conf
  mkdir -p /storj-bucket/${chunkId}
  rclone mount $chunkId: /storj-bucket/${chunkId} \
    --daemon \
    --vfs-read-chunk-size 64K \
    --vfs-read-chunk-size-limit 256K \
    --buffer-size 0 \
    --vfs-read-wait 1ms \
    --max-read-ahead 0 \
    --vfs-cache-mode full \
    --read-only \
    --no-checksum \
    --no-modtime \
    --use-mmap \
    --no-check-certificate \
    --vfs-cache-max-age 1h \
    --timeout 1h \
    --log-level NOTICE \
    --config /tmp/${chunkId}.conf
  mountExist=$(mount | grep /storj-bucket/${chunkId} | wc -l)
  if [[ "$mountExist" -gt 0 ]]; then
    echo "mount chunk $chunkId success"
    return 0
  else
    echo "mount chunk $chunkId failed"
    return 1
  fi
}

function checkPlot() {
  start=$(date +%s)
  chunkDetail=$1
  chunkId=$(echo $chunkDetail | jq -r '.id')
  plotName=$(echo $chunkDetail | jq -r '.plotName')
  echo "scan plot $plotName chunkId $chunkId"
  chia plots check -n 1 -g $plotName >/dev/null 2>/tmp/${plotName}.txt &
  checkPid=$!
  sleep 3
  while true; do
    if [[ "$(ps -ef | grep $checkPid | grep -v grep | wc -l)" -eq 0 ]]; then
      break
    fi
    now=$(date +%s)
    if [[ "$((now - start))" -gt 20 ]]; then
      echo "scan plot $plotName chunkId $chunkId timeout"
      kill -9 $checkPid >/dev/null 2>&1
    fi
    sleep 3
  done
  badbitFound=$(cat /tmp/${plotName}.txt | grep "badbit" | wc -l)
  successScan=$(cat /tmp/${plotName}.txt | grep "done, loaded 1 plots" | wc -l)
  if [[ "$badbitFound" -gt 0 ]]; then
    echo "badbit found in plot $plotName chunkId $chunkId"
    return 1
  fi
  if [[ "$successScan" -eq 0 ]]; then
    echo "scan plot $plotName chunkId $chunkId failed"
    return 1
  fi
  if [[ "$successScan" -gt 0 ]]; then
    echo "scan plot $plotName chunkId $chunkId success"
    return 0
  fi
  return 1
}

while true; do
  # get one chunk from api
  chunk=$(curl -s -X GET "${baseUrl}/chunk?apiKey=${apiKey}&status=done&limit=1&sortBy=lastCheck")
  success=$(echo $chunk | jq '.success')
  if [[ "$success" == "false" ]]; then
    echo "no storj error found, sleep for 60 minutes"
    sleep 3600
    continue
  fi
  chunkDetail=$(echo $chunk | jq '.results[0]')
  chunkLastCheck=$(echo $chunkDetail | jq '.lastCheck')
  if [[ "$chunkLastCheck" != "null" ]]; then
    echo "no chunk with null last check found, sleep for 60 minutes"
    sleep 3600
    continue
  fi
  chunkId=$(echo $chunkDetail | jq -r '.id')
  echo "processing chunk $chunkId"
  mountChunk "$chunkDetail"
  if [[ "$?" != "0" ]]; then
    submitUpdate $chunkId "limit"
    clearUp "$chunkDetail"
    continue
  fi
  checkPlot "$chunkDetail"
  if [[ "$?" != "0" ]]; then
    submitUpdate $chunkId "limit"
    clearUp "$chunkDetail"
    continue
  fi
  submitUpdate $chunkId "done"
  clearUp "$chunkDetail"

done
