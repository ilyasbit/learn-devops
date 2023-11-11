#!/bin/env bash

chia start node farmer-only wallet

trap "echo Shutting down ...; chia stop all -d; exit 0" SIGINT SIGTERM
sleep 10
function syncAllWallet() {
  while true; do
    fullnodeSynced=$(chia rpc full_node get_blockchain_state | jq '.blockchain_state.sync.synced')
    if [[ "$fullnodeSynced" == "true" ]]; then
      break
    fi
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
}

syncAllWallet &

tail -f $CHIA_ROOT/log/debug.log
