#!/usr/bin/env bash
# 监控与运维面板

monitor_image() {
  case "$1" in
    uptime-kuma) echo "louislam/uptime-kuma:1" ;;
    dozzle)      echo "ghcr.io/amir20/dozzle:latest" ;;
    portainer)   echo "portainer/portainer-ce:latest" ;;
  esac
}

install_monitor() {
  log_step "监控与运维面板"

  local services=() name
  for name in uptime-kuma dozzle portainer; do
    stack_preflight_image "$(monitor_image "$name")" && services+=("$name")
  done

  [[ ${#services[@]} -gt 0 ]] || { log_warn "没有可用镜像，跳过 monitor"; return 0; }

  dc monitor up -d "${services[@]}"
  wait_healthy uptime-kuma 60 || true

  # 站点映射：uptime-kuma 监听 3001，dozzle 8080，portainer 9000
  add_site monitor "$(env_get DOMAIN_MONITOR)" "http://uptime-kuma:3001" || true
  add_site dozzle "$(env_get DOMAIN_MONITOR)" "http://dozzle:8080" || true
  add_site portainer "$(env_get DOMAIN_PORTAINER)" "http://portainer:9000" || true

  if [[ -z "$(env_get DOMAIN_MONITOR)" && -z "$(env_get DOMAIN_PORTAINER)" ]]; then
    log_warn "没有为监控面板配置域名，它们只在 Docker 内网里可达"
    log_dim "想用的话在 .env 填 DOMAIN_MONITOR / DOMAIN_PORTAINER 后重跑：./vps install monitor"
  fi

  log_ok "监控栈已启动：${services[*]}"
}
