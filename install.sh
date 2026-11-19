#!/usr/bin/env bash
set -Eeuo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO

DRY_RUN=false
FORCE=false
EXPLICIT=false

# shellcheck source=lib/log.sh
. "$REPO/lib/log.sh"
# shellcheck source=lib/detect.sh
. "$REPO/lib/detect.sh"
# shellcheck source=lib/config.sh
. "$REPO/lib/config.sh"
# shellcheck source=lib/secrets.sh
. "$REPO/lib/secrets.sh"
# shellcheck source=lib/templates.sh
. "$REPO/lib/templates.sh"
# shellcheck source=lib/state.sh
. "$REPO/lib/state.sh"
# shellcheck source=lib/repo.sh
. "$REPO/lib/repo.sh"
# shellcheck source=lib/compose.sh
. "$REPO/lib/compose.sh"
# shellcheck source=lib/site.sh
. "$REPO/lib/site.sh"

# shellcheck source=bootstrap/base.sh
. "$REPO/bootstrap/base.sh"
# shellcheck source=bootstrap/docker.sh
. "$REPO/bootstrap/docker.sh"
# shellcheck source=bootstrap/firewall.sh
. "$REPO/bootstrap/firewall.sh"
# shellcheck source=bootstrap/ssh.sh
. "$REPO/bootstrap/ssh.sh"
# shellcheck source=stacks/caddy/install.sh
. "$REPO/stacks/caddy/install.sh"
# shellcheck source=stacks/proxy/install.sh
. "$REPO/stacks/proxy/install.sh"
# shellcheck source=stacks/monitor/install.sh
. "$REPO/stacks/monitor/install.sh"
# shellcheck source=stacks/apps/install.sh
. "$REPO/stacks/apps/install.sh"

ALL_STEPS=(base docker firewall ssh caddy proxy monitor apps)

usage() {
  cat <<EOF
用法：sudo ./install.sh [选项]

选项：
  --only <列表>    只执行指定步骤，逗号分隔。显式指定的步骤即使之前成功过也会重跑
                   可选：${ALL_STEPS[*]}
  --force          忽略完成记录，全部重跑
  --dry-run        只打印将要执行的步骤，不做任何改动
  -h, --help       显示这段帮助

步骤说明：
  base      系统基础包、时区、swap、内核与网络调优、自动安全更新
  docker    Docker Engine + Compose 插件、容器日志上限
  firewall  ufw 放行 SSH/80/443/代理端口，fail2ban 保护 SSH
  ssh       关闭密码登录（仅在已有公钥时生效）
  caddy     Caddy 反向代理，自动申请 HTTPS 证书
  proxy     sing-box：VLESS+REALITY 与 Hysteria2
  monitor   Uptime Kuma / Dozzle / Portainer
  apps      Alist / Vaultwarden / Memos

环境开关（.env）：
  ENABLE_CADDY / ENABLE_PROXY / ENABLE_MONITOR / ENABLE_APPS
  ENABLE_SSH_HARDENING / ENABLE_SWAP
EOF
}

# ---------------------------------------------------------------- 配置准备

valid_email() { [[ "$1" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; }

prepare_env() {
  if [[ -f "$REPO/.env" ]]; then
    load_env_file "$REPO/.env"
    log_ok "已载入 $REPO/.env"
  elif $DRY_RUN; then
    load_env_file "$REPO/.env.example"
    log_warn "还没有 .env，按 .env.example 的默认值模拟"
  else
    log_step "首次配置"
    cp "$REPO/.env.example" "$REPO/.env"
    chmod 600 "$REPO/.env"
    load_env_file "$REPO/.env"
    log_ok "已从 .env.example 生成 .env"

    # 非交互环境（curl | bash、CI）没有 /dev/tty，不能卡在提问里
    if [[ -e /dev/tty ]]; then
      local email=""
      while ! valid_email "$email"; do
        email="$(ask "Let's Encrypt 通知邮箱（申请证书必填）：")"
        [[ -z $email ]] && { log_warn "邮箱不能为空"; continue; }
        valid_email "$email" || log_warn "邮箱格式看起来不对：$email"
      done
      env_set ACME_EMAIL "$email"

      env_set TZ "$(ask "时区（如 Asia/Shanghai）：" "Asia/Shanghai")"

      if ask_yes_no "现在就填写服务域名吗？（可稍后编辑 .env 再重跑）" n; then
        local key label dom
        for key in DOMAIN_MONITOR DOMAIN_PORTAINER DOMAIN_ALIST DOMAIN_VAULT DOMAIN_MEMOS; do
          case "$key" in
            DOMAIN_MONITOR)   label="监控面板" ;;
            DOMAIN_PORTAINER) label="Portainer" ;;
            DOMAIN_ALIST)     label="Alist" ;;
            DOMAIN_VAULT)     label="Vaultwarden" ;;
            DOMAIN_MEMOS)     label="Memos" ;;
          esac
          dom="$(ask "  ${label} 域名（留空跳过）：")"
          [[ -n $dom ]] && env_set "$key" "$dom"
        done
      fi
    else
      log_warn "非交互环境，跳过提问。请先编辑 $REPO/.env 填好 ACME_EMAIL 和域名"
    fi
  fi

  if ! $DRY_RUN; then
    # 补齐首次运行需要的默认值
    if [[ -z "$(env_get SSH_PORT)" ]]; then
      env_set SSH_PORT "$(detect_ssh_port)"
      log_dim "检测到 SSH 端口：$(env_get SSH_PORT)"
    fi
    [[ -z "$(env_get SSH_USER)" ]] && env_set SSH_USER root
    [[ -z "$(env_get LOG_LEVEL)" ]] && env_set LOG_LEVEL warn
    chmod 600 "$REPO/.env"
  fi
}

# ---------------------------------------------------------------- 各步骤

step_base()    { setup_base; setup_swap; setup_sysctl; setup_auto_upgrade; }
step_docker()  { install_docker; docker network create edge >/dev/null 2>&1 || true; }
step_firewall() { setup_firewall; setup_fail2ban; }
step_ssh()     { harden_ssh; }
step_caddy()   { if env_is_true ENABLE_CADDY; then install_caddy; else log_dim "ENABLE_CADDY=false，跳过"; fi }
step_proxy()   { if env_is_true ENABLE_PROXY; then install_proxy; else log_dim "ENABLE_PROXY=false，跳过"; fi }
step_monitor() { if env_is_true ENABLE_MONITOR; then install_monitor; else log_dim "ENABLE_MONITOR=false，跳过"; fi }
step_apps()    { if env_is_true ENABLE_APPS; then install_apps; else log_dim "ENABLE_APPS=false，跳过"; fi }

step_description() {
  case "$1" in
    base)     echo "系统基础包、swap、内核调优、自动安全更新" ;;
    docker)   echo "Docker Engine + Compose" ;;
    firewall) echo "ufw + fail2ban" ;;
    ssh)      echo "SSH 仅公钥登录" ;;
    caddy)    echo "Caddy 反向代理 + 自动 HTTPS" ;;
    proxy)    echo "sing-box：VLESS+REALITY / Hysteria2" ;;
    monitor)  echo "Uptime Kuma / Dozzle / Portainer" ;;
    apps)     echo "Alist / Vaultwarden / Memos" ;;
  esac
}

# ---------------------------------------------------------------- 汇总

summary() {
  local ip domain key
  ip="$(public_ip)"

  printf '\n'
  log_step "完成"
  printf '  服务器 IP  %s\n' "${ip:-未知}"
  printf '  SSH        %s@%s -p %s\n' "$(env_get SSH_USER root)" "${ip:-<ip>}" "$(env_get SSH_PORT 22)"

  local -a rows=()
  for key in DOMAIN_MONITOR DOMAIN_PORTAINER DOMAIN_ALIST DOMAIN_VAULT DOMAIN_MEMOS; do
    domain="$(env_get "$key")"
    [[ -n $domain ]] && rows+=("https://$domain")
  done
  if [[ ${#rows[@]} -gt 0 ]]; then
    printf '  已绑定域名\n'
    local r
    for r in "${rows[@]}"; do printf '    · %s\n' "$r"; done
  else
    printf '  已绑定域名  （无）\n'
  fi

  if env_is_true ENABLE_PROXY && [[ -n "$(env_get PROXY_UUID)" ]]; then
    printf '  代理端口    REALITY %s / Hysteria2 %s\n' \
      "$(env_get PROXY_REALITY_PORT 8443)" "$(env_get PROXY_HY2_PORT 8444)"
  fi

  env_is_true ENABLE_APPS && apps_post_install_notes

  printf '\n'
  log_info "常用命令"
  printf '    ./vps status          查看所有容器状态\n'
  printf '    ./vps links           输出代理订阅链接和二维码\n'
  printf '    ./vps logs caddy      跟踪某个 stack 的日志\n'
  printf '    ./vps update          拉取新镜像并重建\n'
  printf '    ./vps doctor          体检\n'

  if env_is_true ENABLE_SSH_HARDENING && step_done ssh; then
    printf '\n'
    log_warn "SSH 已改为仅公钥登录 —— 先开一个新终端确认能登录，再关掉当前这个"
  fi
}

# ---------------------------------------------------------------- 主流程

main() {
  local only="" step
  local -a steps=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --only) only="${2:-}"; shift 2 ;;
      --only=*) only="${1#*=}"; shift ;;
      --force) FORCE=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) log_err "未知参数：$1"; usage; exit 1 ;;
    esac
  done

  require_root "$@"
  detect_os
  prepare_env
  init_state "$REPO/state"
  init_sites

  if [[ -n $only ]]; then
    EXPLICIT=true
    # 用 IFS=',' read 而不是 local IFS=',' —— 后者会连带把 ${ALL_STEPS[*]} 的
    # 连接符也改成逗号，下面的成员校验就永远匹配不上
    local -a parts=()
    IFS=',' read -ra parts <<<"$only"
    for step in "${parts[@]}"; do
      [[ -n $step ]] || continue
      [[ " ${ALL_STEPS[*]} " == *" $step "* ]] || die "未知步骤：$step（可选：${ALL_STEPS[*]}）"
      steps+=("$step")
    done
  else
    steps=("${ALL_STEPS[@]}")
  fi

  # 显式 --only 或 --force 时，即使之前成功过也要重跑 —— 否则改完 .env
  # 想只重新部署某个 stack，却会被完成记录静默跳过
  should_skip() {
    $FORCE && return 1
    $EXPLICIT && return 1
    step_done "$1"
  }

  log_step "执行计划"
  for step in "${steps[@]}"; do
    if should_skip "$step"; then
      printf '  %-10s %s已完成，将跳过%s\n' "$step" "$C_DIM" "$C_RESET"
    else
      printf '  %-10s %s\n' "$step" "$(step_description "$step")"
    fi
  done
  printf '  配置文件   %s\n' "$REPO/.env"

  if $DRY_RUN; then
    log_info "--dry-run，未做任何改动"
    exit 0
  fi
  printf '\n'
  ask_yes_no "开始执行？" y || { log_info "已取消"; exit 0; }

  for step in "${steps[@]}"; do
    if should_skip "$step"; then
      log_dim "跳过 ${step}（已完成；单独重跑：sudo ./install.sh --only ${step}）"
      continue
    fi
    "step_$step"
    mark_step "$step"
  done

  # 站点配置可能在 caddy 启动之后才写入，统一重载一次
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx caddy; then
    reload_caddy
  fi

  summary
  printf '\n  配置已保存在 %s，请自行备份（里面有所有密钥）\n\n' "$REPO/.env"
}

trap 'log_err "第 ${LINENO} 行执行失败：${BASH_COMMAND}"
      log_dim "修好问题后直接重跑，已完成的步骤会自动跳过；要重跑某一步：sudo ./install.sh --only <步骤>"' ERR

main "$@"
