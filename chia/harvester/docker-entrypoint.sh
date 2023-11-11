if [[ -n "${TZ}" ]]; then
  echo "Setting timezone to ${TZ}"
  ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime && echo "$TZ" >/etc/timezone
fi

if [[ ! -d "/root/ca" ]]; then
  echo "no ca directory found"
  exit 1
fi

chia init -c /root/ca

if [[ ! -d /root/.worker/mount ]]; then
  echo "no mount directory found"
  exit 1
fi

chia configure --log-level INFO
yq -i '.self_hostname = "0.0.0.0"' "$CHIA_ROOT/config/config.yaml"
yq -i '.harvester.recursive_plot_scan = true' "$CHIA_ROOT/config/config.yaml"
yq -i ".harvester.farmer_peer.host = \"$FARMER_HOST\"" "$CHIA_ROOT/config/config.yaml"
