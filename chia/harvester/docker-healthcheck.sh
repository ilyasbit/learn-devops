if [[ ${healthcheck} != "true" ]]; then
  exit 0
fi
dt() {
  date +%FT%T.%3N
}

logger() {
  echo "$1" >>"${CHIA_ROOT}/log/debug.log"
}

curl -X POST --fail \
  --cert "${CHIA_ROOT}/config/ssl/harvester/private_harvester.crt" \
  --key "${CHIA_ROOT}/config/ssl/harvester/private_harvester.key" \
  -d '{}' -k -H "Content-Type: application/json" https://127.0.0.1:8560/healthz

if [[ "$?" -ne 0 ]]; then
  logger "$(dt) harvester healthcheck failed"
  exit 1
fi

logger "$(dt) Healthcheck(s) completed successfully"
