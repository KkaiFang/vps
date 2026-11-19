#!/usr/bin/env bash
# 系统探测

detect_os() {
  [[ -r /etc/os-release ]] || die "读不到 /etc/os-release，无法判断系统版本"
  # shellcheck disable=SC1091
  . /etc/os-release

  OS_ID="${ID:-unknown}"
  OS_CODENAME="${VERSION_CODENAME:-}"
  OS_NAME="${PRETTY_NAME:-$OS_ID}"
  ARCH="$(dpkg --print-architecture)"

  case "$OS_ID" in
    debian|ubuntu) ;;
    *) die "目前只支持 Debian / Ubuntu，检测到：$OS_NAME" ;;
  esac

  log_ok "系统：${OS_NAME}（${ARCH}，代号 ${OS_CODENAME}）"
}

# sshd 实际监听的端口，取不到就退回 22
detect_ssh_port() {
  local port=""
  if have sshd; then
    port="$(sshd -T 2>/dev/null | awk 'tolower($1)=="port" {print $2; exit}' || true)"
  fi
  printf '%s' "${port:-22}"
}

public_ip() {
  local url ip
  for url in https://api.ipify.org https://ipv4.icanhazip.com https://ifconfig.me/ip; do
    ip="$(curl -4fsS --max-time 6 "$url" 2>/dev/null || true)"
    [[ -n "$ip" ]] && { printf '%s' "$ip"; return 0; }
  done
  printf ''
}

# 是否已有 swap
has_swap() {
  [[ -n "$(swapon --show --noheadings 2>/dev/null)" ]]
}
