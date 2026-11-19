#!/usr/bin/env bash
# Caddy 反向代理
#
# Caddy 是唯一对外监听 80/443 的容器。其他服务全部只用容器名在内网 edge 上通信，
# 不发布端口 —— 少一个公网端口就少一个攻击面。

install_caddy() {
  log_step "Caddy 反向代理"

  local acme_email caddyfile="$REPO/stacks/caddy/Caddyfile"

  acme_email="$(env_get ACME_EMAIL)"
  if [[ -z $acme_email || $acme_email = "you@example.com" ]]; then
    log_err "ACME_EMAIL 未设置 —— 申请证书需要一个真实邮箱"
    log_dim "编辑 $REPO/.env，把 ACME_EMAIL 改成你自己的邮箱后重跑"
    return 1
  fi

  # 故意不装 apt 的 caddy 包：它会注册一个占着 80/443 的 systemd 服务，
  # 和下面这个容器直接抢端口
  if systemctl list-unit-files 2>/dev/null | grep -q '^caddy\.service'; then
    log_warn "检测到系统里装了 caddy 服务，先停掉它，否则容器绑不上 80/443"
    systemctl disable --now caddy >/dev/null 2>&1 || true
  fi

  docker network create edge >/dev/null 2>&1 || true

  render_file "$REPO/stacks/caddy/Caddyfile.tmpl" "$caddyfile" "ACME_EMAIL=$acme_email"
  assert_rendered "$caddyfile"

  dc caddy up -d

  # 配置语法有问题时不让它悄悄带着旧配置继续跑
  if ! dc caddy exec -T caddy caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
    log_err "Caddyfile 校验失败，查看日志：docker logs caddy"
    return 1
  fi

  log_ok "Caddy 已启动（80 / 443 / 443udp）"
}

reload_caddy() {
  if ! docker ps --format '{{.Names}}' | grep -qx caddy; then
    log_dim "Caddy 未运行，跳过重载"
    return 0
  fi
  if dc caddy exec -T caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null; then
    log_ok "Caddy 配置已重载"
  else
    log_warn "Caddy 重载失败，执行 docker restart caddy 试试"
  fi
}
