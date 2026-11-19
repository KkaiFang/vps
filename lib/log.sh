#!/usr/bin/env bash
# 终端输出与通用断言

if [[ -t 1 ]] && [[ "${TERM:-dumb}" != "dumb" ]]; then
  C_RESET=$'\033[0m'
  C_RED=$'\033[0;31m'
  C_GREEN=$'\033[0;32m'
  C_YELLOW=$'\033[0;33m'
  C_BLUE=$'\033[0;36m'
  C_DIM=$'\033[2m'
else
  C_RESET=''
  C_RED=''
  C_GREEN=''
  C_YELLOW=''
  C_BLUE=''
  C_DIM=''
fi

# 所有日志走 stderr —— stdout 只留给真正的数据输出，
# 否则 $(ensure_secret ...) 这类命令替换会把日志行一起吞进变量里
log_info() { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*" >&2; }
log_ok()   { printf '%s  ok%s %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
log_warn() { printf '%swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_err()  { printf '%sfail%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
log_dim()  { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET" >&2; }
log_step() { printf '\n%s── %s ──%s\n' "$C_BLUE" "$*" "$C_RESET" >&2; }

die() {
  log_err "$*"
  exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "请用 root 运行：sudo $0 $*"
}

# 幂等地安装 apt 包：只装缺的那些
apt_install() {
  local missing=() pkg
  for pkg in "$@"; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then
      missing+=("$pkg")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    log_dim "已安装：$*"
    return 0
  fi

  log_info "安装软件包：${missing[*]}"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${missing[@]}"
}

# 交互式读取，永远从 /dev/tty 读，这样 curl | bash 也能用
ask() {
  local msg="$1" def="${2:-}" answer=""
  if [[ ! -e /dev/tty ]]; then
    printf '%s' "$def"
    return 0
  fi
  printf '%s' "$msg" >/dev/tty
  IFS= read -r answer </dev/tty || answer=""
  printf '%s' "${answer:-$def}"
}

ask_yes_no() {
  local msg="$1" def="${2:-n}" answer
  answer="$(ask "$msg " "$def")"
  [[ "$answer" =~ ^[Yy] ]]
}
