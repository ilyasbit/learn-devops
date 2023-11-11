if [[ -n "${TZ}" ]]; then
  echo "Setting timezone to ${TZ}"
  ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime && echo "$TZ" >/etc/timezone
fi

if [ "$(grep -c "^*                soft     nproc          65535$" /etc/security/limits.conf)" -eq 0 ]; then
  echo "*                soft     nproc          65535" >>/etc/security/limits.conf
fi

if [ "$(grep -c "^*                hard     nproc          65535$" /etc/security/limits.conf)" -eq 0 ]; then
  echo "*                hard     nproc          65535" >>/etc/security/limits.conf
fi

if [ "$(grep -c "^*                soft     nofile         65535$" /etc/security/limits.conf)" -eq 0 ]; then
  echo "*                soft     nofile         65535" >>/etc/security/limits.conf
fi

if [ "$(grep -c "^*                hard     nofile         65535$" /etc/security/limits.conf)" -eq 0 ]; then
  echo "*                hard     nofile         65535" >>/etc/security/limits.conf
fi

if [ "$(grep -c "^root             soft     nproc          65535$" /etc/security/limits.conf)" -eq 0 ]; then
  echo "root             soft     nproc          65535" >>/etc/security/limits.conf
fi

if [ "$(grep -c "^root             hard     nproc          65535$" /etc/security/limits.conf)" -eq 0 ]; then
  echo "root             hard     nproc          65535" >>/etc/security/limits.conf
fi

if [ "$(grep -c "^root             soft     nofile         65535$" /etc/security/limits.conf)" -eq 0 ]; then
  echo "root             soft     nofile         65535" >>/etc/security/limits.conf
fi

if [ "$(grep -c "^root             hard     nofile         65535$" /etc/security/limits.conf)" -eq 0 ]; then
  echo "root             hard     nofile         65535" >>/etc/security/limits.conf
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

function mountRclone() {
  file=$1
  mountId=$2

}

function mountConfig() {

  ls -1 /root/.worker/mount/*.conf | while read file; do
    rclone config show --config /root/.worker/mount/${file} | grep "MOUNT" | while read line; do
      mountId=$(echo ${line} | awk '{print $2}')
      mountRclone ${file} ${mountId}
    done
  done

}

function rcloneMountConfig() {
  ls -1 /root/.worker/mount/*.conf | while read file; do
    echo "rclone mount ${file}"

  done
}
