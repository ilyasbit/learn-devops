#!/bin/env bash

function mountRclone() {
  fullPath=$1
  remoteName=$2
  mountpoint="/storj-bucket/${remoteName}"
  mkdir -p $mountpoint
  mkdir -p ~/.worker/log/mount
  echo "Mounting $remoteName to $mountpoint"
  rclone mount $remoteName $mountpoint \
    --allow-other \
    --transfers 64 \
    --vfs-read-chunk-size 64K \
    --buffer-size 0 \
    --vfs-read-wait 1ms \
    --max-read-ahead 0 \
    --vfs-cache-mode full \
    --vfs-cache-max-size 5G \
    --vfs-fast-fingerprint \
    --read-only \
    --no-checksum \
    --no-modtime \
    --use-mmap \
    --no-check-certificate \
    --vfs-cache-max-age 1440h \
    --log-level INFO \
    --timeout 1h \
    --config $fullPath \
    --log-file ~/.worker/log/mount/${remoteName}.log \
    --user-agent s3cli &

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

trap "echo Shutting down ...; chia stop all -d; exit 0" SIGINT SIGTERM

tail -f $CHIA_ROOT/log/debug.log
