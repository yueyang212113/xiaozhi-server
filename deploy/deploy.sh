#!/bin/bash
set -e

cd "$(dirname "$0")"

# 如果没有 .env 文件则从模板创建
if [ ! -f .env ]; then
  cp .env.example .env
  echo "已创建 .env 文件，请修改其中的配置后重新运行"
  exit 1
fi

source .env

echo "=== 部署开始 ==="
echo "镜像标签: ${IMAGE_TAG}"

echo "[1/3] 拉取最新镜像..."
docker compose pull

echo "[2/3] 重启服务..."
docker compose up -d --remove-orphans

echo "[3/3] 清理旧镜像..."
docker image prune -f

echo "=== 部署完成 ==="
docker compose ps
