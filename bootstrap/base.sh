#!/usr/bin/env bash
# 基础系统配置：时区、软件包、swap、内核与服务端调优

setup_base() {
  log_step "基础环境"

  apt-get update -qq
  apt_install \
    curl ca-certificates gnupg openssl jq \
    ufw fail2ban unattended-upgrades \
    htop vim-tiny rsync cron logrotate

  if [[ -n "$(env_get TZ)" ]]; then
    ln -sf "/usr/share/zoneinfo/$(env_get TZ)" /etc/localtime
    echo "$(env_get TZ)" >/etc/timezone
    log_ok "时区设为 $(env_get TZ)"
  fi

  # 确保 cron / logrotate 在跑，unattended-upgrades 依赖 systemd timer
  systemctl enable --now cron >/dev/null 2>&1 || log_warn "cron 未启动"
  systemctl enable --now unattended-upgrades >/dev/null 2>&1 || log_warn "unattended-upgrades 未启动"
}

setup_swap() {
  env_is_true ENABLE_SWAP || { log_dim "swap 已在配置中关闭"; return 0; }

  if has_swap; then
    log_dim "已存在 swap，跳过"
    return 0
  fi

  local size file=/swapfile
  size="$(env_get SWAP_SIZE 2G)"

  log_info "创建 ${size} swap"
  if command -v fallocate >/dev/null 2>&1; then
    fallocate -l "$size" "$file" || dd if=/dev/zero of="$file" bs=1M count="$(( ${size%G} * 1024 ))" status=none
  else
    dd if=/dev/zero of="$file" bs=1M count="$(( ${size%G} * 1024 ))" status=none
  fi
  chmod 600 "$file"
  mkswap "$file" >/dev/null
  swapon "$file"

  if ! grep -qE "^${file}[[:space:]]" /etc/fstab; then
    echo "$file none swap sw 0 0" >>/etc/fstab
  fi

  # 小内存机器上早点用 swap，避免 OOM 直接杀进程
  [[ -f /etc/sysctl.d/99-vps-tuning.conf ]] || cat >/etc/sysctl.d/99-vps-tuning.conf <<'EOF'
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF

  log_ok "swap 已启用"
}

setup_sysctl() {
  log_info "应用内核与网络调优"
  cat >/etc/sysctl.d/99-vps-tuning.conf <<'EOF'
# BBR 拥塞控制
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 连接队列
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 8192

# 文件句柄
fs.file-max = 1000000
fs.inotify.max_user_watches = 524288

# 端口范围
net.ipv4.ip_local_port_range = 1024 65535

# TCP 回收
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1

# 内存
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF

  sysctl --system >/dev/null
  log_ok "内核参数已生效（BBR：$(sysctl -n net.ipv4.tcp_congestion_control)）"
}

setup_auto_upgrade() {
  log_info "启用自动安全更新"

  cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

  # 原版配置只安装安全更新；需要重启时不会自动重启，避免把服务重启断线
  cat >/etc/apt/apt.conf.d/51unattended-upgrades-vps <<'EOF'
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

  log_ok "自动安全更新已开启"
}
