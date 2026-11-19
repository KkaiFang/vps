#!/usr/bin/env bash
# ufw 防火墙
#
# 关键顺序：先把 SSH 端口放开，再启用 ufw，否则会把自己锁在门外。

setup_firewall() {
  log_step "防火墙"

  local ssh_port proxy_ports=() port
  ssh_port="$(env_get SSH_PORT 22)"

  if env_is_true ENABLE_PROXY; then
    proxy_ports+=("$(env_get PROXY_REALITY_PORT 8443)")
    proxy_ports+=("$(env_get PROXY_HY2_PORT 8444)")
  fi

  # 先放行，不管 ufw 当前是开是关
  ufw allow "${ssh_port}/tcp" comment 'ssh' >/dev/null
  ufw allow 80/tcp comment 'http-acme' >/dev/null
  ufw allow 443/tcp comment 'https' >/dev/null
  ufw allow 443/udp comment 'http3' >/dev/null
  for port in ${proxy_ports[@]+"${proxy_ports[@]}"}; do
    ufw allow "${port}/tcp" comment 'proxy' >/dev/null
    ufw allow "${port}/udp" comment 'proxy' >/dev/null
  done

  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null

  if ufw status | grep -q '^Status: active'; then
    ufw reload >/dev/null
    log_ok "防火墙已更新规则"
  else
    ufw --force enable >/dev/null
    log_ok "防火墙已启用"
  fi

  log_dim "已放行：tcp ${ssh_port}, 80, 443${proxy_ports:+，代理 tcp+udp ${proxy_ports[*]}}"
  log_dim "docker 容器若要发布额外端口，注意 docker 会绕过 ufw —— 优先用 Caddy 反代，或只监听 127.0.0.1"
}

# fail2ban：只保护 sshd，避免误伤 Caddy 的 443
setup_fail2ban() {
  log_step "fail2ban"

  local ssh_port
  ssh_port="$(env_get SSH_PORT 22)"

  log_info "配置 fail2ban"
  # systemd 后端需要 python3-systemd，不装的话 jail 起不来
  apt_install python3-systemd >/dev/null 2>&1 || true

  cat >/etc/fail2ban/jail.d/vps.local <<EOF
[DEFAULT]
backend  = systemd
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled  = true
port     = ${ssh_port}
EOF

  systemctl enable fail2ban >/dev/null 2>&1
  systemctl restart fail2ban
  log_ok "fail2ban 已保护 sshd（${ssh_port}，5 次失败封 1 小时）"
}
