#!/usr/bin/env bash
# SSH 加固
#
# 只在服务器上已经存在至少一个公钥时才关闭密码登录 —— 否则就是把自己锁死。
# 改动写进 99 前缀的 drop-in，sshd 后加载覆盖，不动发行版原配置。

harden_ssh() {
  log_step "SSH"

  local ssh_port user ssh_dir auth_keys
  ssh_port="$(env_get SSH_PORT 22)"
  user="$(env_get SSH_USER root)"

  if [[ "$user" = root ]]; then
    ssh_dir=/root/.ssh
  else
    ssh_dir="$(getent passwd "$user" | cut -d: -f6)/.ssh"
  fi
  auth_keys="$ssh_dir/authorized_keys"

  if [[ ! -s "$auth_keys" ]]; then
    log_warn "$auth_keys 不存在或为空 —— 没有可用公钥，保持密码登录不变"
    log_warn "请先上传公钥，然后重跑：sudo ./install.sh --only ssh"
    return 0
  fi

  if ! env_is_true ENABLE_SSH_HARDENING; then
    log_dim "SSH 加固已在配置中关闭"
    return 0
  fi

  local dropin=/etc/ssh/sshd_config.d/99-vps-hardening.conf
  mkdir -p "$(dirname "$dropin")"

  log_info "写入 SSH 加固配置"
  cat >"$dropin" <<EOF
# 由 vps 仓库生成
Port ${ssh_port}
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
  [[ -s $dropin ]] || die "写入 $dropin 失败"

  # 先验证语法，配置写坏时不让 sshd 重启，保住现有的连接入口
  sshd -t || die "sshd 配置校验失败，已保留原配置，请检查 $dropin"

  if ! { systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; }; then
    die "已写入配置但没能重载 sshd，请手动确认：systemctl status ssh"
  fi

  log_ok "SSH 已加固：端口 ${ssh_port}，仅公钥登录"
  log_warn "别关当前终端！在开新窗口验证能登录之后再退出"
}
