curl -X POST --fail \
  --cert "${CHIA_ROOT}/config/ssl/farmer/private_farmer.crt" \
  --key "${CHIA_ROOT}/config/ssl/farmer/private_farmer.key" \
  -d '{}' -k -H "Content-Type: application/json" https://127.0.0.1:8560/healthz
