#!/usr/bin/env bash
# 执行状态记录。重跑时自动跳过已成功的步骤，避免把生成好的密钥又覆盖一次。

STATE_DIR=""

init_state() {
  STATE_DIR="$1"
  mkdir -p "$STATE_DIR"
}

step_done() {
  [[ -n $STATE_DIR && -f "$STATE_DIR/$1.done" ]]
}

mark_step() {
  [[ -n $STATE_DIR ]] || return 0
  date -Iseconds >"$STATE_DIR/$1.done" 2>/dev/null || : >"$STATE_DIR/$1.done"
}

clear_step() {
  [[ -n $STATE_DIR ]] || return 0
  rm -f "$STATE_DIR/$1.done"
}

# 带跳过逻辑的步骤包装：step_run <名字> <函数>
step_run() {
  local name="$1"
  shift
  if step_done "$name"; then
    log_dim "跳过 ${name}（已完成）"
    return 0
  fi
  "$@"
  mark_step "$name"
}
