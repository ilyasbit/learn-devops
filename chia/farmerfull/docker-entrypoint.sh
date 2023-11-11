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

exec "$@"
