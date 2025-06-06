#!/bin/bash

echo "=== 一键初始化安装脚本 ==="
sedi() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i "" "$@"
  else
    sed -i "$@"
  fi
}
echo "📁 检查并复制代理文件：tmp/proxies.txt → backend/proxy/proxies.txt"
if [[ -f tmp/proxies.txt ]]; then
  mkdir -p backend/proxy
  cp tmp/proxies.txt backend/proxy/proxies.txt
  echo "✅ 已复制 proxies.txt"
else
  echo "❌ 未找到 tmp/proxies.txt，请先准备代理列表！"
  exit 1
fi
echo "📁 检查并复制用户key文件：tmp/user_keys.txt → backend/user/user_keys.txt"
if [[ -f tmp/user_keys.txt ]]; then
  mkdir -p backend/user
  cp tmp/user_keys.txt backend/user/user_keys.txt
  echo "✅ 已复制 user_keys.txt"
else
  echo "❌ 未找到 tmp/user_keys.txt，请先准备用户key列表！"
  exit 1
fi

BASE_API_URL="http://backend:8000"
SSL_MODE="off"

# 是否使用 SSL
read -p "是否启用 SSL？[y/N]: " use_ssl
use_ssl=${use_ssl:-N}

if [[ "$use_ssl" =~ ^[Yy]$ ]]; then
  echo "🔍 检查 tmp/ 下的 SSL 证书文件..."

  mkdir -p frontend/ssl

  crt_file=$(find tmp/ -type f -name "*.crt" | head -n1)
  key_file=$(find tmp/ -type f -name "*.key" | head -n1)
  pem_files=($(find tmp/ -type f -name "*.pem"))

  if [[ -n "$crt_file" && -n "$key_file" ]]; then
    cp "$crt_file" frontend/ssl/server.crt
    cp "$key_file" frontend/ssl/server.key
    echo "✅ 使用现有 .crt 和 .key 文件"
  elif [[ ${#pem_files[@]} -eq 1 ]]; then
    echo "🔧 检测到 1 个 PEM 文件，尝试拆分证书和密钥..."
    openssl x509 -in "${pem_files[0]}" -out frontend/ssl/server.crt -outform PEM
    openssl pkey -in "${pem_files[0]}" -out frontend/ssl/server.key
    if [[ $? -ne 0 ]]; then
      echo "❌ PEM 拆分失败，请检查格式"
      exit 1
    fi
    echo "✅ 成功从 PEM 拆出证书和密钥"
  elif [[ ${#pem_files[@]} -ge 2 ]]; then
    echo " 🧩 检测到多个 PEM 文件，请选择哪个是证书："
    select crt_path in "${pem_files[@]}"; do
      [[ -n "$crt_path" && "$crt_path" != "$key_path" ]] && break
    done
    echo "🔍 检测到多个 PEM 文件，请选择哪个是密钥："
    select key_path in "${pem_files[@]}"; do
      [[ -n "$key_path" ]] && break
    done
    cp "$crt_path" frontend/ssl/server.crt
    cp "$key_path" frontend/ssl/server.key
    echo "✅ 已复制用户指定的 PEM 文件"
  else
    echo "❌ 未找到证书文件（.crt/.key/.pem）"
    exit 1
  fi

  BASE_API_URL="https://backend:8000"
  SSL_MODE="on"
else
  BASE_API_URL="http://backend:8000"
  SSL_MODE="off"
fi

# 写入 .env
echo "BASE_API_URL=$BASE_API_URL" > .env
echo "DOCKER_API_URL=http://backend:8000" >> .env
echo "✅ 已写入 .env"

# 替换 nginx.conf
if [[ "$SSL_MODE" == "on" ]]; then
  nginx_template="tmp/nginx.ssl.template"
else
  nginx_template="tmp/nginx.conf.template"
fi
if [[ ! -f "$nginx_template" ]]; then
  echo "❌ 找不到 nginx 模板文件: $nginx_template"
  exit 1
fi
cp "$nginx_template" frontend/nginx.conf


# 容器内访问地址
if [[ "$SSL_MODE" == "on" ]]; then
  final_wss_url="wss://backend:8000/worker/"
else
  final_wss_url="ws://backend:8000/worker/"
fi
# 创建 brush-net 网络（如不存在）
docker network inspect brush-net >/dev/null 2>&1 || docker network create brush-net

# 启动容器（刷上网络）
echo "🚀 正在启动容器..."
docker compose --env-file .env up -d --remove-orphans

echo "✅ 容器启动完成！"

# 提示信息
echo
echo "管理后台地址：ip:8080"
echo "api 地址：ip:8080/api"
echo "wss 地址：ip:8080/ws/worker/"
echo "记得加协议头"
echo