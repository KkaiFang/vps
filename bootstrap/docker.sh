#!/usr/bin/env bash
# Docker Engine + Compose 插件

install_docker() {
  log_step "Docker"

  if have docker; then
    log_dim "Docker 已安装：$(docker --version)"
  else
    install_docker_repo
    apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    log_ok "Docker 安装完成：$(docker --version)"
  fi

  systemctl enable --now docker >/dev/null

  # 日志轮转。不设上限的话容器日志能把磁盘写满
  if [[ ! -f /etc/docker/daemon.json ]]; then
    mkdir -p /etc/docker
    cat >/etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "3"
  },
  "live-restore": true
}
EOF
    systemctl restart docker
    log_ok "已配置容器日志上限 20m × 3"
  fi

  docker compose version >/dev/null 2>&1 || die "docker compose 插件不可用"
  docker info >/dev/null 2>&1 || die "Docker 守护进程未正常运行"
  log_ok "Docker 运行正常"
}
