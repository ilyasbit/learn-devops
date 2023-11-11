#!/usr/bin/env bash

if [[ -n "${TZ}" ]]; then
  echo "Setting timezone to ${TZ}"
  ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime && echo "$TZ" >/etc/timezone
fi

if [[ -d /root/.chia/mainnet/config/ssl ]]; then
  echo "ssl folder found, not initialize chia ssl"
elif [[ -d /root/ca ]]; then
  chia init -c /root/ca
else
  chia init
fi
chia init --fix-ssl-permissions

keyListFile="/root/keyList.txt"

if [[ ! -f ${keyListFile} ]]; then
  echo "No keyList.txt found, exiting"
  exit 1
fi

while read -r line; do
  if [[ -z "${line}" ]]; then
    continue
  fi
  seed=$(echo "${line}" | cut -d'|' -f1)
  profile=$(echo "${line}" | cut -d'|' -f2)
  echo $seed >/tmp/seed.txt
  if [[ -n "${profile}" ]]; then
    chia ${chia_args} keys add -f /tmp/seed.txt -l "${profile}"
  else
    chia ${chia_args} keys add -f /tmp/seed.txt
  fi
done <"${keyListFile}"
rm -rf /tmp/seed.txt

chia configure --log-level INFO

yq -i '.self_hostname = "0.0.0.0"' "$CHIA_ROOT/config/config.yaml"
yq -i '.harvester.recursive_plot_scan = true' "$CHIA_ROOT/config/config.yaml"

chia start harvester -r

function syncAllWallet() {
  while true; do
    fullnodeSynced=$(chia rpc full_node get_blockchain_state | jq '.blockchain_state.sync.synced')
    if [[ "$fullnodeSynced" == "true" ]]; then
      break
    fi
    echo "Waiting for fullnode sync"
    sleep 10
  done
  chia rpc wallet get_public_keys | jq -r '.public_key_fingerprints[]' | while read fingerprint; do
    chia rpc wallet log_in "{ \"fingerprint\": $fingerprint }"
    while true; do
      walletSyncStatus=$(chia rpc wallet get_sync_status | jq -r '.synced')
      if [[ "$walletSyncStatus" == "true" ]]; then
        break
        sleep 10
      fi
    done
  done
  firstWallet=$(chia rpc wallet get_public_keys | jq -r '.public_key_fingerprints[]' | head -n1)
  chia rpc wallet log_in "{ \"fingerprint\": $firstWallet }"
  echo "switched to first wallet"
}

syncAllWallet

exec "$@"
