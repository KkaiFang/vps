#!/usr/bin/env bash
# .env 读写。故意不用 source —— 值里出现特殊字符时不会被 shell 解释，
# 也不会把后加的键污染成已存在的 shell 变量。

ENV_FILE=""

load_env_file() {
  local path="$1"
  [[ -f "$path" ]] || die "找不到配置文件：$path"
  ENV_FILE="$path"
}

env_get() {
  local key="$1" default="${2:-}" val=""
  if [[ -n $ENV_FILE ]]; then
    val="$(grep -E "^[[:space:]]*${key}=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
  fi
  # 去掉首尾空白和一对引号
  val="${val#"${val%%[![:space:]]*}"}"
  val="${val%"${val##*[![:space:]]}"}"
  if [[ ${#val} -ge 2 ]]; then
    case "$val" in
      \"*\"|\'*\') val="${val:1:${#val}-2}" ;;
    esac
  fi
  printf '%s' "${val:-$default}"
}

env_is_true() {
  local v
  v="$(env_get "$1" "${2:-false}")"
  [[ "$v" =~ ^(true|TRUE|yes|YES|1|on|ON)$ ]]
}

# 写回 .env。键存在就替换，不存在就追加。
env_set() {
  local key="$1" val="$2" tmp
  [[ -n $ENV_FILE ]] || die "未加载配置文件，不能写入"
  tmp="$(mktemp)"
  awk -v k="$key" -v v="$val" '
    BEGIN { FS = OFS = "="; done = 0 }
    $1 == k { if (!done) { print k "=" v; done = 1 }; next }
    { print }
    END { if (!done) print k "=" v }
  ' "$ENV_FILE" >"$tmp"
  cat "$tmp" >"$ENV_FILE"
  rm -f "$tmp"
  chmod 600 "$ENV_FILE"
}

# 需要填写的必填项检查
require_env() {
  local key missing=()
  for key in "$@"; do
    [[ -n "$(env_get "$key")" ]] || missing+=("$key")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    die "以下配置项为空，请先填写（${ENV_FILE}）：${missing[*]}"
  fi
}
