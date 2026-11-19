#!/usr/bin/env bash
# 代理节点：VLESS + REALITY 与 Hysteria2
#
# REALITY 不需要域名和证书，靠借用一个境外大站的 TLS 握手来伪装；
# Hysteria2 用自签证书，客户端跳过校验即可。
# 两个入站都监听在 sing-box 里，端口由 ufw 放行。

PROXY_DIR=""

proxy_image() {
  printf 'ghcr.io/sagernet/sing-box:%s' "$(env_get SINGBOX_VERSION latest)"
}

# 用镜像自带的 generate reality-keypair 生成密钥对，输出到全局变量。
# 输出是 PrivateKey / PublicKey 两行，别和旧版 xray 的 Password 字段搞混。
generate_reality_keypair() {
  local out
  if ! out="$(docker run --rm "$(proxy_image)" generate reality-keypair 2>&1)"; then
    log_err "生成 REALITY 密钥失败，原始输出："
    printf '%s\n' "$out" >&2
    return 1
  fi

  REALITY_PRIVATE_KEY="$(printf '%s\n' "$out" | sed -n 's/^PrivateKey: *//p' | head -n1)"
  REALITY_PUBLIC_KEY="$(printf '%s\n' "$out" | sed -n 's/^PublicKey: *//p' | head -n1)"

  if [[ -z $REALITY_PRIVATE_KEY || -z $REALITY_PUBLIC_KEY ]]; then
    log_err "解析 REALITY 密钥失败，原始输出："
    printf '%s\n' "$out" >&2
    return 1
  fi
  return 0
}

# Hysteria2 用自签证书。域名优先取 .env 配置，没有域名就用公网 IP 作为 SAN
setup_hy2_cert() {
  local cert="$PROXY_DIR/certs/fullchain.pem"
  local key="$PROXY_DIR/certs/privkey.pem"
  local sni san

  mkdir -p "$PROXY_DIR/certs"

  sni="$(env_get PROXY_HY2_SNI)"
  [[ -z $sni ]] && sni="$(first_domain)"
  if [[ -z $sni ]]; then
    sni="$(public_ip)"
    [[ -n $sni ]] || sni="localhost"
  fi
  # 记下来，给分享链接用
  env_set PROXY_HY2_SNI "$sni"

  if [[ $sni =~ ^[0-9.]+$ ]]; then
    san="IP:${sni}"
  else
    san="DNS:${sni}"
  fi

  if [[ -s $cert && -s $key ]]; then
    log_dim "Hysteria2 证书已存在（CN=${sni}）"
    return 0
  fi

  log_info "生成 Hysteria2 自签证书（CN=${sni}）"
  openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout "$key" -out "$cert" -days 3650 \
    -subj "/CN=${sni}" -addext "subjectAltName=${san}" 2>/dev/null \
    || die "生成自签证书失败"
  chmod 644 "$cert"
  chmod 600 "$key"
  log_ok "证书有效期 10 年"
}

install_proxy() {
  log_step "代理节点（VLESS+REALITY / Hysteria2）"

  PROXY_DIR="$REPO/stacks/proxy"
  mkdir -p "$PROXY_DIR/config"

  # 先确认镜像可用：后面生成密钥也要用它
  stack_preflight_image "$(proxy_image)" || die "sing-box 镜像不可用，检查 .env 里的 SINGBOX_VERSION"

  setup_hy2_cert

  # 凭据：已存在就复用，不会因为重跑而让客户端全部失效
  local uuid password short_id mask_host
  uuid="$(ensure_secret PROXY_UUID)"
  short_id="$(ensure_secret PROXY_REALITY_SHORT_ID)"
  password="$(ensure_secret PROXY_HY2_PASSWORD)"

  if [[ -z "$(env_get PROXY_REALITY_PRIVATE_KEY)" ]]; then
    log_info "生成 REALITY 密钥对"
    generate_reality_keypair || die "REALITY 密钥生成失败"
    env_set PROXY_REALITY_PRIVATE_KEY "$REALITY_PRIVATE_KEY"
    env_set PROXY_REALITY_PUBLIC_KEY "$REALITY_PUBLIC_KEY"
    log_ok "REALITY 密钥已保存到 .env"
  fi

  # 别人拿浏览器直接访问 Hysteria2 端口时看到的内容。
  # 要选一个在国内能正常打开、看起来人畜无害的站点 —— 伪装到一个打不开的站点反而更显眼
  mask_host="$(env_get PROXY_HY2_MASQUERADE)"
  [[ -z $mask_host ]] && mask_host="www.bing.com"

  log_info "渲染 sing-box 配置"
  render_file "$PROXY_DIR/config.tmpl" "$PROXY_DIR/config/config.json" \
    "LOG_LEVEL=$(env_get LOG_LEVEL warn)" \
    "PROXY_UUID=$uuid" \
    "PROXY_REALITY_SNI=$(env_get PROXY_REALITY_SNI)" \
    "PROXY_REALITY_PORT=$(env_get PROXY_REALITY_PORT 8443)" \
    "PROXY_REALITY_PRIVATE_KEY=$(env_get PROXY_REALITY_PRIVATE_KEY)" \
    "PROXY_REALITY_SHORT_ID=$short_id" \
    "PROXY_HY2_PORT=$(env_get PROXY_HY2_PORT 8444)" \
    "PROXY_HY2_PASSWORD=$password" \
    "MASK_HOST=$mask_host"
  chmod 600 "$PROXY_DIR/config/config.json"
  assert_rendered "$PROXY_DIR/config/config.json"

  log_info "启动 sing-box"
  dc proxy up -d

  sleep 2
  if ! docker ps --format '{{.Names}}' | grep -qx proxy; then
    log_err "proxy 容器未能启动，最近日志："
    docker logs --tail 20 proxy >&2 || true
    return 1
  fi
  if docker logs proxy 2>&1 | grep -qiE 'FATAL|panic|invalid config'; then
    log_err "配置有误，最近日志："
    docker logs --tail 20 proxy >&2 || true
    return 1
  fi

  log_ok "sing-box 已启动：REALITY $(env_get PROXY_REALITY_PORT 8443) / Hysteria2 $(env_get PROXY_HY2_PORT 8444)"
  log_dim "生成分享链接：./vps links"
}
