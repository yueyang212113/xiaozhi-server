#!/bin/bash
# xiaozhi-esp32-server ECS 初始化脚本
# 在 ECS 上以 root 用户执行

set -e

echo "=== 1. 安装 Docker ==="
if command -v docker &> /dev/null; then
    echo "Docker 已安装: $(docker --version)"
else
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker && systemctl start docker
    echo "Docker 安装完成"
fi

echo "=== 2. 安装 Docker Compose 插件 ==="
if docker compose version &> /dev/null; then
    echo "Docker Compose 已安装: $(docker compose version)"
else
    apt-get update && apt-get install -y docker-compose-plugin
    echo "Docker Compose 安装完成"
fi

echo "=== 3. 创建目录结构 ==="
mkdir -p /opt/xiaozhi/data/{xiaozhi-server/data,xiaozhi-server/models,mysql,redis,uploadfile}
mkdir -p /opt/xiaozhi/nginx/conf.d

echo "=== 4. 登录阿里云 ACR ==="
echo "请输入 ACR 密码:"
docker login --username=aliyun0674656790 crpi-7jk2cw21xgpicom2.cn-beijing.personal.cr.aliyuncs.com

echo "=== 5. 创建 docker-compose.yml ==="
cat > /opt/xiaozhi/docker-compose.yml << 'COMPOSE_EOF'
version: "3.8"

services:
  mysql:
    image: mysql:8
    container_name: xiaozhi-mysql
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_PASSWORD}
      MYSQL_DATABASE: xiaozhi_esp32_server
    volumes:
      - ./data/mysql:/var/lib/mysql
    ports:
      - "127.0.0.1:3306:3306"
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 10

  redis:
    image: redis:7
    container_name: xiaozhi-redis
    restart: always
    volumes:
      - ./data/redis:/data
    ports:
      - "127.0.0.1:6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3

  xiaozhi-server:
    image: ${ACR_REGISTRY}/${ACR_NAMESPACE}/xiaozhi-server:${IMAGE_TAG}
    container_name: xiaozhi-server
    restart: always
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_healthy
    ports:
      - "8000:8000"
      - "8003:8003"
    security_opt:
      - seccomp:unconfined
    environment:
      - TZ=Asia/Shanghai
    volumes:
      - ./data/xiaozhi-server/data:/opt/xiaozhi-esp32-server/data
      - ./data/xiaozhi-server/models:/opt/xiaozhi-esp32-server/models

  manager-web:
    image: ${ACR_REGISTRY}/${ACR_NAMESPACE}/xiaozhi-manager-web:${IMAGE_TAG}
    container_name: xiaozhi-manager-web
    restart: always
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_healthy
    ports:
      - "8002:8002"
    environment:
      - TZ=Asia/Shanghai
      - SPRING_DATASOURCE_DRUID_URL=jdbc:mysql://mysql:3306/xiaozhi_esp32_server?useUnicode=true&characterEncoding=UTF-8&serverTimezone=Asia/Shanghai&nullCatalogMeansCurrent=true
      - SPRING_DATASOURCE_DRUID_USERNAME=root
      - SPRING_DATASOURCE_DRUID_PASSWORD=${MYSQL_PASSWORD}
      - SPRING_DATA_REDIS_HOST=redis
      - SPRING_DATA_REDIS_PASSWORD=
      - SPRING_DATA_REDIS_PORT=6379
    volumes:
      - ./data/uploadfile:/uploadfile

  manager-mobile:
    image: ${ACR_REGISTRY}/${ACR_NAMESPACE}/xiaozhi-manager-mobile:${IMAGE_TAG}
    container_name: xiaozhi-manager-mobile
    restart: always
    ports:
      - "9000:80"
    environment:
      - TZ=Asia/Shanghai
COMPOSE_EOF

echo "=== 6. 创建 .env 配置 ==="
cat > /opt/xiaozhi/.env << 'ENV_EOF'
# 阿里云 ACR 配置
ACR_REGISTRY=crpi-7jk2cw21xgpicom2.cn-beijing.personal.cr.aliyuncs.com
ACR_NAMESPACE=yueyang212113-xiaozhi

# 镜像标签
IMAGE_TAG=dev-latest

# MySQL root 密码（请修改为强密码）
MYSQL_PASSWORD=Xiaozhi@2026
ENV_EOF

echo "=== 7. 创建 deploy.sh ==="
cat > /opt/xiaozhi/deploy.sh << 'DEPLOY_EOF'
#!/bin/bash
set -e
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  cp .env.example .env
  echo "已创建 .env 文件，请修改配置后重新运行"
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
DEPLOY_EOF
chmod +x /opt/xiaozhi/deploy.sh

echo "=== 8. 首次部署 ==="
cd /opt/xiaozhi
docker compose pull
docker compose up -d

echo ""
echo "============================================"
echo "  部署完成！"
echo "  - WebSocket: ws://$(hostname -I | awk '{print $1}'):8000"
echo "  - 管理后台:  http://$(hostname -I | awk '{print $1}'):8002"
echo "  - 移动端:    http://$(hostname -I | awk '{print $1}'):9000"
echo ""
echo "  注意：请修改 /opt/xiaozhi/.env 中的 MYSQL_PASSWORD"
echo "============================================"
