#!/usr/bin/env bash
# 把服务挂到域名后面

CADDY_SITES_DIR=""

init_sites() {
  CADDY_SITES_DIR="$REPO/stacks/caddy/sites"
  mkdir -p "$CADDY_SITES_DIR"
}

# 已填写的域名列表
configured_domains() {
  local key val
  for key in DOMAIN_MONITOR DOMAIN_PORTAINER DOMAIN_ALIST DOMAIN_VAULT DOMAIN_MEMOS; do
    val="$(env_get "$key")"
    [[ -n $val ]] && printf '%s\n' "$val"
  done
}

first_domain() {
  # 用 awk 读完整行而不是 head —— head 提前退出会让上游收到 SIGPIPE，
  # 在 set -o pipefail 下被当成命令失败
  configured_domains | awk 'NR == 1 { print }'
}

# add_site <标识> <域名> <上游> [额外指令]
# 域名为空表示不开放这个站点，同时删掉旧配置（改配置后重跑能正确下线）
add_site() {
  local name="$1" domain="$2" upstream="$3" extra="${4:-}"
  local file="$CADDY_SITES_DIR/$name.caddy"

  if [[ -z $domain ]]; then
    if [[ -f $file ]]; then
      rm -f "$file"
      log_dim "${name}：域名已清空，站点配置已移除"
    fi
    return 1
  fi

  local extra_block=""
  if [[ -n $extra ]]; then
    # 额外指令前留一个空行，和 reverse_proxy 块分开
    extra_block="
	${extra}"
  fi

  cat >"$file" <<EOF
# 由 install.sh 生成，勿手改 —— 改 .env 里的 DOMAIN_* 后重跑 install.sh
$domain {
	encode zstd gzip

	# 真实客户端 IP，方便应用层做限流和日志
	reverse_proxy $upstream {
		header_up X-Real-IP {remote_host}
		header_up X-Forwarded-For {remote_host}
	}${extra_block}
}
EOF

  chmod 644 "$file"
  log_ok "${name}：https://$domain → $upstream"
  return 0
}
