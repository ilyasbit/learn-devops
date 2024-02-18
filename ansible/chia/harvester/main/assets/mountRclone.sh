#!/bin/env bash

source ~/.worker/env

while [[ "$(which chia)" == "" ]]; do
  . /opt/chia-blockchain/activate
done

function mountRclone() {
  fullPath=$1
  remoteName=$2
  mountpoint="/storj-bucket/${remoteName}"
  mkdir -p $mountpoint
  mkdir -p ~/.worker/log/mount
  echo "Mounting $remoteName to $mountpoint"
  rclone mount $remoteName $mountpoint \
    --allow-other \
    --vfs-read-chunk-size 64K \
    --vfs-read-chunk-size-limit 256K \
    --buffer-size 0 \
    --vfs-read-wait 1ms \
    --max-read-ahead 0 \
    --vfs-cache-mode full \
    --vfs-cache-max-size $CACHESIZE \
    --read-only \
    --no-checksum \
    --no-modtime \
    --use-mmap \
    --no-check-certificate \
    --vfs-cache-max-age 10000h \
    --timeout 1h \
    --log-level NOTICE \
    --log-file ~/.worker/log/mount/${remoteName}.log \
    --config $fullPath \
    --user-agent s3cli \
    --daemon
  #--vfs-fast-fingerprint \
  while true; do
    if [[ "$(mount | grep $mountpoint | wc -l)" -gt 0 ]]; then
      echo "Mounting $remoteName to $mountpoint success"
      break
    fi
    sleep 3
  done
}

function mountConfig() {
  ls -1 /root/.worker/mount/*.conf | while read file; do
    fullPath=$(realpath $file)
    rclone listremotes --config $fullPath | grep "MOUNT-COMPACT" | while read line; do
      mountRclone $fullPath $line
    done
  done
}

mountConfig

chia start harvester

#tail -f $CHIA_ROOT/log/debug.log
