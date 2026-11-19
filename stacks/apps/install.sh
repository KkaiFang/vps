#!/usr/bin/env bash
# 自托管应用：Alist / Vaultwarden / Memos

app_image() {
  case "$1" in
    alist)       echo "xhofe/alist:latest" ;;
    vaultwarden) echo "vaultwarden/server:latest" ;;
    memos)       echo "neosmemo/memos:stable" ;;
  esac
}

install_apps() {
  log_step "自托管应用"

  local services=() name
  for name in alist vaultwarden memos; do
    stack_preflight_image "$(app_image "$name")" && services+=("$name")
  done

  [[ ${#services[@]} -gt 0 ]] || { log_warn "没有可用镜像，跳过 apps"; return 0; }

  # Vaultwarden 后台令牌：不填就不能登录 /admin，但也不影响正常使用
  if [[ -n "$(env_get VAULT_ADMIN_TOKEN)" || " ${services[*]} " == *" vaultwarden "* ]]; then
    ensure_secret VAULT_ADMIN_TOKEN >/dev/null
  fi

  dc apps up -d "${services[@]}"
  wait_healthy vaultwarden 60 || true
  wait_healthy alist 60 || true

  add_site alist "$(env_get DOMAIN_ALIST)" "http://alist:5244" || true
  add_site vault "$(env_get DOMAIN_VAULT)" "http://vaultwarden:80" || true
  add_site memos "$(env_get DOMAIN_MEMOS)" "http://memos:5230" || true

  log_ok "应用栈已启动：${services[*]}"
}

# 首次部署后需要人工完成的初始化，集中打印，免得去翻文档
apps_post_install_notes() {
  local shown=0
  local -a notes=()

  if docker ps --format '{{.Names}}' | grep -qx alist; then
    notes+=("Alist 初始密码：docker exec -it alist ./alist admin random")
    shown=1
  fi
  if docker ps --format '{{.Names}}' | grep -qx vaultwarden; then
    notes+=("Vaultwarden 注册第一个账号前先确认 SIGNUPS_ALLOWED，注册完改成 false 并重跑")
    notes+=("Vaultwarden 后台令牌：grep VAULT_ADMIN_TOKEN .env")
    shown=1
  fi
  if docker ps --format '{{.Names}}' | grep -qx memos; then
    notes+=("Memos 首个注册的账号自动成为管理员")
    shown=1
  fi

  (( shown )) || return 0
  printf '\n'
  log_info "应用初始化提示"
  local n
  for n in "${notes[@]}"; do
    printf '    · %s\n' "$n"
  done
}
