#!/usr/bin/env bash
# 模板渲染：{{KEY}} 占位符替换
#
# 用 sed 而不是 envsubst —— envsubst 会依赖环境变量，把 .env 里的值
# export 出来既麻烦又有注入风险。这里只替换显式传入的键。

_sed_escape() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

# render_file <模板> <输出> [KEY=VALUE ...]
render_file() {
  local src="$1" dest="$2" pair key val
  local -a expr=()
  shift 2

  [[ -f "$src" ]] || die "模板不存在：$src"

  # 用数组传参，值里带空格也不会被拆开
  for pair in "$@"; do
    key="${pair%%=*}"
    val="${pair#*=}"
    expr+=(-e "s|{{${key}}}|$(_sed_escape "$val")|g")
  done

  sed "${expr[@]}" "$src" >"$dest"
}

# 校验渲染结果里没有漏掉的占位符
assert_rendered() {
  local file="$1" left
  left="$(grep -oE '\{\{[A-Z0-9_]+\}\}' "$file" | sort -u | tr '\n' ' ' || true)"
  [[ -z $left ]] || die "$(basename "$file") 中还有未替换的占位符：$left"
}

# 写文件并确保权限
write_secure() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
  cat >"$dest"
  chmod "${2:-600}" "$dest"
}
