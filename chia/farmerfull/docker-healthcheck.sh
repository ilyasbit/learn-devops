#!/bin/env bash

if [[ ${healthcheck} != "true" ]]; then
  exit 0
fi
dt() {
  date +%FT%T.%3N
}

logger() {
  echo "$1" >>"${CHIA_ROOT}/log/debug.log"
}

nc -z -v -w1 localhost 55400
# shellcheck disable=SC2181
if [[ "$?" -ne 0 ]]; then
  logger "$(dt) Daemon healthcheck failed"
  exit 1
fi

curl -X POST --fail \
  --cert "${CHIA_ROOT}/config/ssl/full_node/private_full_node.crt" \
  --key "${CHIA_ROOT}/config/ssl/full_node/private_full_node.key" \
  -d '{}' -k -H "Content-Type: application/json" https://127.0.0.1:8555/healthz

# shellcheck disable=SC2181
if [[ "$?" -ne 0 ]]; then
  logger "$(dt) Node healthcheck failed"
  exit 1
fi

curl -X POST --fail \
  --cert "${CHIA_ROOT}/config/ssl/farmer/private_farmer.crt" \
  --key "${CHIA_ROOT}/config/ssl/farmer/private_farmer.key" \
  -d '{}' -k -H "Content-Type: application/json" https://127.0.0.1:8559/healthz

# shellcheck disable=SC2181
if [[ "$?" -ne 0 ]]; then
  logger "$(dt) Farmer healthcheck failed"
  exit 1
fi

logger "$(dt) Healthcheck(s) completed successfully"
