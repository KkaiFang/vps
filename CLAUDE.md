# 项目约定

一个"新 VPS 一键部署"仓库。Shell + Docker Compose，目标系统 Debian 12 / Ubuntu 22.04+。

## 代码风格

- 所有脚本 `#!/usr/bin/env bash` + `set -Eeuo pipefail`
- 日志一律走 `log_*`（输出到 stderr），**stdout 只用于真正的数据**，因为 `$(ensure_secret ...)` 这类命令替换会把 stdout 吞进变量
- 字符串里变量后面紧跟中文时用 `${var}`，别用 `$var` —— 某些 locale 下会被当成变量名的一部分
- 注释、日志、README 都用中文
- 不引入 ansible 之类的外部依赖，只用 Debian 自带的 bash / curl / openssl / jq

## 结构

- `install.sh` 只做流程编排，具体逻辑在 `bootstrap/`（系统层）和 `stacks/`（服务层）
- 每个 `stacks/<名字>/` 是一个独立的 compose 项目，自带 `compose.yaml` 和 `install.sh`
- 服务通过 Docker 内网 `edge` 通信，对外只靠 Caddy 反代；新增服务不要发布宿主机端口
- 幂等是硬要求：重跑不能覆盖已生成的密钥，不能重复追加 fstab / sysctl 配置

## 配置

- 所有配置走根目录 `.env`，新增配置项要同步加到 `.env.example` 并在 README 里说明
- 站点域名用 `DOMAIN_*`，留空表示不对外暴露
- 模板用 `{{KEY}}` 占位符 + `render_file`，渲染后 `assert_rendered` 检查有没有漏替换

## 改完必须验证

没有测试套件，靠真跑：

```bash
bash -n install.sh vps lib/*.sh bootstrap/*.sh stacks/*/install.sh
docker run --rm -v "$PWD:/repo" debian:12 bash -c 'cd /repo && ./install.sh --dry-run'
```

涉及 sing-box 配置的改动，用 `sing-box check` 校验渲染结果；涉及 Caddy 的用 `caddy validate`。
