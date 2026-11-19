#!/usr/bin/env bash
# 软件源

install_docker_repo() {
  if [[ -s /etc/apt/sources.list.d/docker.list ]] && [[ -f /etc/apt/keyrings/docker.asc ]]; then
    log_dim "Docker 源已存在"
    return 0
  fi

  log_info "配置 Docker 官方源"
  apt_install ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  local channel="stable"
  # Debian 用的是 codename，Ubuntu 也是
  cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${OS_ID} ${OS_CODENAME} ${channel}
EOF

  apt-get update -qq
  log_ok "Docker 源已配置"
}
