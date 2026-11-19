#!/usr/bin/env bash
# docker compose 包装
#
# 所有 stack 共用仓库根目录的 .env。compose 默认只读自身目录的 .env，
# 所以这里显式传 --env-file，保证变量插值来源只有一个。

dc() {
  local stack="$1"
  shift
  docker compose \
    --env-file "$REPO/.env" \
    -f "$REPO/stacks/$stack/compose.yaml" \
    "$@"
}

# 预检镜像是否可用。
# 官方镜像 404 时往往要 sudo 才能跑，直接把“镜像名还没确认”这件事说清楚，
# 比让人对着 compose 的 404 报错猜要省事。
stack_preflight_image() {
  local image="$1"
  if docker image inspect "$image" >/dev/null 2>&1; then
    return 0
  fi

  log_info "拉取镜像 $image"
  if docker pull -q "$image" >/dev/null 2>&1; then
    log_ok "镜像可用：$image"
    return 0
  fi

  log_warn "拉不到镜像 ${image}（可能改名或仓库调整），跳过这个服务"
  log_dim "确认正确名称后修改 compose.yaml 里的 image，再重跑 install.sh"
  return 1
}

# 等待容器健康，最多 timeout 秒
wait_healthy() {
  local name="$1" timeout="${2:-60}" i=0 status
  while (( i < timeout )); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name" 2>/dev/null || echo missing)"
    case "$status" in
      healthy|running) return 0 ;;
      missing|exited|dead) log_warn "$name 状态：$status"; return 1 ;;
    esac
    sleep 2
    i=$((i + 2))
  done
  log_warn "$name 在 ${timeout}s 内未就绪（当前：${status:-unknown}）"
  return 1
}
