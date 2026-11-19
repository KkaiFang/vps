#!/usr/bin/env bash
# 随机值生成

rand_hex() {
  local n="${1:-16}"
  openssl rand -hex "$n"
}

# 标准 base64，去掉填充以外的空白
rand_b64() {
  local n="${1:-32}"
  openssl rand -base64 "$n" | tr -d '\n'
}

# URL 安全、无填充的 base64 —— sing-box 的 UUID / REALITY 密钥都用这个格式
rand_b64_url() {
  local n="${1:-32}"
  openssl rand -base64 "$n" | tr -d '\n=' | tr '+/' '-_'
}

rand_uuid() {
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
  else
    openssl rand -hex 16 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/'
  fi
}

rand_password() {
  # 十六进制避免管道里的 head -c：提前关闭管道会触发 SIGPIPE，
  # 在 pipefail 下会让整个脚本退出
  openssl rand -hex 16
}

# 从 .env 读取，为空则生成并写回，最后输出值
ensure_secret() {
  local key="$1" val
  val="$(env_get "$key")"
  if [[ -z $val ]]; then
    case "$key" in
      *UUID*) val="$(rand_uuid)" ;;
      *SHORT_ID*) val="$(rand_hex 8)" ;;
      *) val="$(rand_password)" ;;
    esac
    env_set "$key" "$val"
    log_ok "已生成 $key"
  fi
  printf '%s' "$val"
}
