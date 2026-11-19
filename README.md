# vps

新买一台 VPS 之后，一条命令把要用的服务全部装好：系统加固 + Docker + 反向代理 + 代理节点 + 监控面板 + 自托管应用。

面向 Debian 12 / Ubuntu 22.04+。所有密钥都在服务器本地生成、只写进 `.env`，仓库里没有任何敏感信息，可以公开。

## 用法

新机器上，直接用 root 跑：

```bash
# 用 git（机器上没装 git 的话：apt update && apt install -y git）
git clone https://github.com/<你的用户名>/vps.git /root/vps
cd /root/vps
sudo ./install.sh

# 或者不装 git，直接下载压缩包
curl -fsSL https://codeload.github.com/<你的用户名>/vps/tar.gz/refs/heads/main \
  | tar xz -C /root && cd /root/vps-main
sudo ./install.sh
```

第一次运行会引导你填写证书邮箱、时区和想用的域名，然后依次执行：

| 步骤 | 内容 |
|---|---|
| `base` | 基础软件包、时区、swap、BBR 与内核网络调优、自动安全更新 |
| `docker` | Docker Engine + Compose 插件，容器日志限制 20m × 3 |
| `firewall` | ufw 放行 SSH / 80 / 443 / 代理端口，fail2ban 保护 SSH |
| `ssh` | 关闭密码登录（**仅在已存在公钥时生效**，否则自动跳过） |
| `caddy` | Caddy，自动申请并续期 HTTPS 证书 |
| `proxy` | sing-box：VLESS + REALITY 与 Hysteria2 |
| `monitor` | Uptime Kuma、Dozzle、Portainer |
| `apps` | Alist、Vaultwarden、Memos |

跑完会打印服务器 IP、SSH 命令、已绑定的域名和常用命令。

## ⚠️ 装之前先看一眼

1. **先把公钥传上去**。脚本发现 `/root/.ssh/authorized_keys` 为空时会自动跳过 SSH 加固，但如果你自己已经改过 sshd，请确认公钥可用再跑。
2. **域名先解析**。填了 `DOMAIN_*` 的域名必须提前 A 记录指向这台机器，否则 Caddy 申请证书会失败（会重试，解析好了之后 `sudo ./install.sh --only caddy` 即可）。
3. **安全组的端口**。云厂商的安全组要在控制台单独放行，脚本只管机器内的 ufw。
4. **Portainer 权限很大**。挂了 docker.sock 就等于 root。要么配 `DOMAIN_PORTAINER` 并设强密码，要么不配域名、用 `ssh -L 9000:localhost:9000` 访问。

## 目录结构

```
.
├── install.sh              # 主安装脚本
├── vps                     # 日常运维命令
├── .env.example            # 配置模板（复制成 .env 使用）
├── lib/                    # 脚本工具库
│   ├── config.sh           #   .env 读写
│   ├── secrets.sh          #   密钥生成（幂等，重跑不会变）
│   ├── templates.sh        #   {{占位符}} 渲染
│   ├── site.sh             #   生成 Caddy 站点配置
│   ├── state.sh            #   步骤完成记录
│   └── compose.sh          #   docker compose 包装
├── bootstrap/              # 系统层：base / docker / firewall / ssh
└── stacks/                 # 服务层，每个目录 = 一个 compose 项目
    ├── caddy/              #   反向代理
    ├── proxy/              #   sing-box 代理节点
    ├── monitor/            #   Uptime Kuma / Dozzle / Portainer
    └── apps/               #   Alist / Vaultwarden / Memos
```

运行时生成、**不会入库**的文件：

- `.env` — 所有配置和密钥，权限 600
- `stacks/caddy/Caddyfile`、`stacks/caddy/sites/*.caddy` — 由模板和域名生成
- `stacks/proxy/config/config.json`、`stacks/proxy/certs/` — sing-box 配置和自签证书
- `state/` — 步骤完成记录

## 配置

所有配置集中在 `.env`，改完重跑对应步骤即可生效：

```bash
sudo ./vps edit                                  # 编辑配置
sudo ./install.sh --only caddy                   # 只重新部署 Caddy
sudo ./install.sh --only proxy,monitor           # 重新部署多个
```

常用项：

| 变量 | 说明 |
|---|---|
| `ACME_EMAIL` | Let's Encrypt 通知邮箱，**必填** |
| `TZ` | 时区，如 `Asia/Shanghai` |
| `ENABLE_CADDY` / `ENABLE_PROXY` / `ENABLE_MONITOR` / `ENABLE_APPS` | 服务开关 |
| `DOMAIN_MONITOR` / `DOMAIN_PORTAINER` / `DOMAIN_ALIST` / `DOMAIN_VAULT` / `DOMAIN_MEMOS` | 站点域名，留空则该服务不对外 |
| `PROXY_REALITY_PORT` / `PROXY_HY2_PORT` | 代理端口，默认 8443 / 8444 |
| `PROXY_REALITY_SNI` | REALITY 伪装目标，需支持 TLS1.3 + H2 的境外站点 |
| `VAULT_SIGNUPS_ALLOWED` | 注册完第一个账号后应改回 `false` |

`.env` 里的空值会在首次安装时自动生成并写回，**不要手动清空它们** —— 清空等于换一套凭据，所有客户端都要重新配置。

## 日常命令

```bash
sudo ./vps status        # 容器状态和监听端口
sudo ./vps links         # 输出代理分享链接（装 qrencode 则同时出二维码）
sudo ./vps logs caddy    # 跟踪某个 stack 的日志
sudo ./vps sites         # 当前生效的域名映射
sudo ./vps update        # 拉新镜像并重建
sudo ./vps doctor        # 体检：端口、防火墙、证书、磁盘、NTP
sudo ./vps down monitor  # 停掉某个 stack
```

代理客户端方面：REALITY 用 sing-box / v2rayN / Shadowrocket / NekoBox 均可，指纹选 `chrome`；Hysteria2 用自签证书，客户端务必开「跳过证书验证」。

## 常见问题

**证书申请失败**
域名没解析到本机、或者安全组没放行 80 端口。确认解析后：`sudo ./install.sh --only caddy`。Caddy 会一直重试，也可以 `sudo ./vps logs caddy` 看原因。

**REALITY 连不上**
1. 时间偏差要小于 30 秒：`sudo ./vps doctor` 看 NTP 状态
2. `PROXY_REALITY_SNI` 必须是支持 TLS1.3 和 H2 的站点
3. 云安全组放行 8443 端口
4. 分享链接里的 `pbk` 是公钥，别和服务端私钥搞混

**改了域名不生效**
`--only` 指定的步骤会重跑，但 Caddy 只在步骤末尾重载一次。如果直接改了 `sites/*.caddy`，执行 `docker exec caddy caddy reload -c /etc/caddy/Caddyfile`。

**想重跑全部**
`sudo ./install.sh --force`。密钥已存在时不会重新生成，客户端不会失效。

**迁移到新机器**
把整个仓库目录（含 `.env`、`stacks/*/config`、`stacks/proxy/certs`）拷到新机器，运行 `sudo ./install.sh`，再把域名 A 记录切过去。注意证书会自动重新申请，旧机器的 Caddy 需要先停掉。

**备份**
要备份的就是 `.env`（和 Caddy 的证书卷 `docker volume`，可选）。丢了 `.env` 就要重配所有客户端。

## 安全说明

- 只有 Caddy 对外监听 80/443，其他服务一律走 Docker 内网 `edge`，不发布宿主机端口
- 代理用 host 网络（为了拿到真实客户端 IP），端口由 ufw 放行
- 容器日志限制在 20m × 3，避免把磁盘写满
- 自动安全更新开启但**不自动重启**，避免服务被意外中断
- Docker 会绕过 ufw 直接发布端口 —— 所以新增服务时宁可走 Caddy 反代，也不要 `ports: - "xxxx:xxxx"`
