# xiaozhi-esp32-server CI/CD + 阿里云 ECS 部署设计

## 1. 概述

将 xiaozhi-esp32-server 项目通过 GitHub Actions 自动化构建 Docker 镜像，推送到阿里云容器镜像服务（ACR），并自动部署到阿里云 ECS 实例上运行。

**目标环境**：阿里云 ECS（2C4G，单台），Docker Compose 编排。

**设计原则**：
- 在 GitHub Actions 上构建镜像，不在低配 ECS 上构建
- 使用阿里云 ACR（个人版免费）存储和分发镜像
- 参数化所有配置，便于未来迁移和多节点扩展
- 渐进式架构：当前单机，预留多机扩展能力

## 2. 整体架构

```
GitHub Push / Tag
       |
       v
GitHub Actions Runner
  +-------------------------+
  | 1. Checkout 代码         |
  | 2. 登录阿里云 ACR         |
  | 3. 构建并推送 Docker 镜像  |
  | 4. SSH 连接 ECS 执行部署   |
  +-------------------------+
       |              |
       v              v
  阿里云 ACR       阿里云 ECS
  (镜像存储)      (运行服务)
                  +------------------+
                  | docker-compose   |
                  | +- xiaozhi-server| :8000 (WS)
                  |                  | :8003 (HTTP)
                  | +- manager-web   | :8002 (Nginx+JRE)
                  | +- manager-mobile| :9000 (Nginx)
                  | +- MySQL 8       | :3306
                  | +- Redis 7       | :6379
                  +------------------+
```

## 3. 服务组件

### 3.1 镜像规划

| 镜像 | 基础镜像 | 说明 | 暴露端口 |
|------|---------|------|---------|
| xiaozhi-server | python:3.10-slim + opus + ffmpeg | Python 核心服务 | 8000, 8003 |
| xiaozhi-manager-web | bellsoft/liberica-runtime-container:jre-17-glibc + nginx | Java API + Vue 前端 | 8002 |
| xiaozhi-manager-mobile | nginx:alpine | UniApp H5 静态文件 | 9000 |
| mysql | mysql:8 | 数据库 | 3306 |
| redis | redis:7 | 缓存 | 6379 |

### 3.2 镜像命名

```
registry.cn-<region>.aliyuncs.com/<namespace>/xiaozhi-server:<tag>
registry.cn-<region>.aliyuncs.com/<namespace>/xiaozhi-manager-web:<tag>
registry.cn-<region>.aliyuncs.com/<namespace>/xiaozhi-manager-mobile:<tag>
```

Tag 规范：
- 开发环境：`dev-<short_sha>`（如 `dev-abc1234`）
- 生产环境：`<version>`（如 `v1.0.0`）

## 4. CI/CD 流水线

### 4.1 开发环境部署（deploy-dev.yml）

**触发条件**：推送到 `main` 分支

**步骤**：
1. Checkout 代码
2. 设置 Docker Buildx（支持缓存）
3. 登录阿里云 ACR
4. 构建并推送 3 个应用镜像（tag: `dev-<short_sha>` + `dev-latest`）
5. SSH 连接 ECS 执行部署命令

**部署命令**：
```bash
cd /opt/xiaozhi
export IMAGE_TAG=dev-latest
docker compose pull
docker compose up -d --remove-orphans
docker image prune -f
```

### 4.2 生产环境部署（deploy-prod.yml）

**触发条件**：推送 `v*` 标签

**步骤**：
1. Checkout 代码
2. 登录阿里云 ACR
3. 构建并推送 3 个应用镜像（tag: 版本号 + `latest`）
4. SSH 连接 ECS 执行部署
5. 健康检查确认（HTTP 200 检测各服务端口）

### 4.3 GitHub Secrets 配置

在 GitHub 仓库 Settings → Secrets and variables → Actions 中配置：

| Secret | 说明 | 示例 |
|--------|------|------|
| `ALIYUN_ACR_REGISTRY` | ACR 实例地址 | `registry.cn-hangzhou.aliyuncs.com` |
| `ALIYUN_ACR_NAMESPACE` | ACR 命名空间 | `xiaozhi` |
| `ALIYUN_ACR_USERNAME` | ACR 登录用户名 | - |
| `ALIYUN_ACR_PASSWORD` | ACR 登录密码 | - |
| `ECS_HOST` | ECS 公网 IP | `123.45.67.89` |
| `ECS_SSH_USER` | SSH 用户名 | `root` |
| `ECS_SSH_KEY` | SSH 私钥 | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `MYSQL_PASSWORD` | MySQL root 密码 | - |

## 5. ECS 部署配置

### 5.1 目录结构

```
/opt/xiaozhi/
├── docker-compose.yml          # 主编排文件
├── .env                        # 环境变量（密码、镜像地址等）
├── deploy.sh                   # 部署脚本
├── nginx/
│   └── conf.d/
│       ├── web.conf            # manager-web 代理配置
│       └── mobile.conf         # manager-mobile 代理配置
├── data/
│   ├── mysql/                  # MySQL 持久化数据
│   ├── redis/                  # Redis 持久化数据
│   ├── xiaozhi-server/
│   │   ├── .config.yaml        # Python 服务配置
│   │   └── models/             # AI 模型文件
│   └── logs/                   # 各服务日志
```

### 5.2 docker-compose.yml

```yaml
version: "3.8"

services:
  mysql:
    image: mysql:8
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_PASSWORD}
      MYSQL_DATABASE: xiaozhi_esp32_server
      MYSQL_CHARSET: utf8mb4
      MYSQL_COLLATION: utf8mb4_unicode_ci
    volumes:
      - ./data/mysql:/var/lib/mysql
      - ./data/mysql-conf:/etc/mysql/conf.d
    ports:
      - "127.0.0.1:3306:3306"
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7
    restart: always
    volumes:
      - ./data/redis:/data
    ports:
      - "127.0.0.1:6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  xiaozhi-server:
    image: ${ACR_REGISTRY}/${ACR_NAMESPACE}/xiaozhi-server:${IMAGE_TAG}
    restart: always
    ports:
      - "8000:8000"
      - "8003:8003"
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_healthy
    volumes:
      - ./data/xiaozhi-server:/app/data
      - ./data/xiaozhi-server/models:/app/models
    environment:
      - TZ=Asia/Shanghai

  manager-web:
    image: ${ACR_REGISTRY}/${ACR_NAMESPACE}/xiaozhi-manager-web:${IMAGE_TAG}
    restart: always
    ports:
      - "8002:8002"
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      - SPRING_PROFILES_ACTIVE=prod
      - MYSQL_HOST=mysql
      - MYSQL_PASSWORD=${MYSQL_PASSWORD}
      - REDIS_HOST=redis
      - TZ=Asia/Shanghai

  manager-mobile:
    image: ${ACR_REGISTRY}/${ACR_NAMESPACE}/xiaozhi-manager-mobile:${IMAGE_TAG}
    restart: always
    ports:
      - "9000:80"
    environment:
      - TZ=Asia/Shanghai
```

### 5.3 .env 文件

```env
ACR_REGISTRY=registry.cn-hangzhou.aliyuncs.com
ACR_NAMESPACE=xiaozhi
IMAGE_TAG=dev-latest
MYSQL_PASSWORD=<your-password>
```

### 5.4 deploy.sh

```bash
#!/bin/bash
set -e

cd /opt/xiaozhi

echo "Pulling latest images..."
docker compose pull

echo "Restarting services..."
docker compose up -d --remove-orphans

echo "Cleaning up old images..."
docker image prune -f

echo "Deployment complete!"
docker compose ps
```

## 6. Dockerfile 设计

### 6.1 xiaozhi-server Dockerfile

基于现有 `Dockerfile-server` 和 `Dockerfile-server-base`，合并为单文件：

```dockerfile
FROM python:3.10-slim

# 安装系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    libopus0 ffmpeg locales && \
    rm -rf /var/lib/apt/lists/*

# 配置中文编码
RUN sed -i '/zh_CN.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8

WORKDIR /app

# 安装 Python 依赖
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/

# 复制应用代码
COPY . .

EXPOSE 8000 8003

CMD ["python", "app.py"]
```

### 6.2 manager-web Dockerfile

基于现有 `Dockerfile-web`，调整 JDK 版本为 17：

```dockerfile
# Stage 1: 构建 Vue 前端
FROM node:18-alpine AS web-builder
WORKDIR /app
COPY main/manager-web/package*.json ./
RUN npm ci
COPY main/manager-web/ .
RUN npm run build

# Stage 2: 构建 Java 后端
FROM maven:3.8-eclipse-temurin-17 AS api-builder
WORKDIR /app
COPY main/manager-api/pom.xml .
RUN mvn dependency:go-offline -B
COPY main/manager-api/src ./src
RUN mvn package -DskipTests -B

# Stage 3: 运行时
FROM bellsoft/liberica-runtime-container:jre-17-glibc
RUN apt-get update && apt-get install -y nginx && rm -rf /var/lib/apt/lists/*
COPY --from=web-builder /app/dist /usr/share/nginx/html
COPY --from=api-builder /app/target/*.jar /app/app.jar
COPY docs/docker/nginx.conf /etc/nginx/nginx.conf
COPY docs/docker/start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 8002
CMD ["/start.sh"]
```

### 6.3 manager-mobile Dockerfile

```dockerfile
# Stage 1: 构建
FROM node:18-alpine AS builder
RUN corepack enable && corepack prepare pnpm@latest --activate
WORKDIR /app
COPY main/manager-mobile/package.json main/manager-mobile/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY main/manager-mobile/ .
RUN pnpm build:h5

# Stage 2: 运行
FROM nginx:alpine
COPY --from=builder /app/dist/build/h5 /usr/share/nginx/html
EXPOSE 80
```

## 7. 前置准备（一次性）

### 7.1 阿里云 ACR 开通

1. 登录阿里云控制台 → 容器镜像服务
2. 创建个人实例（免费）
3. 选择地域（建议与 ECS 同地域，内网拉取免流量费）
4. 创建命名空间（如 `xiaozhi`）
5. 设置 Registry 登录密码

### 7.2 ECS 初始化

```bash
# 安装 Docker
curl -fsSL https://get.docker.com | sh
systemctl enable docker && systemctl start docker

# 安装 Docker Compose
apt-get install docker-compose-plugin

# 创建部署目录
mkdir -p /opt/xiaozhi/{data,nginx/conf.d}

# 配置 SSH 密钥免密登录（将公钥添加到 ECS）
# 本地: ssh-keygen -t ed25519 -f ~/.ssh/xiaozhi_ecs
# ECS:  将公钥追加到 ~/.ssh/authorized_keys

# 登录 ACR（首次拉取需要）
docker login registry.cn-<region>.aliyuncs.com
```

### 7.3 GitHub 配置

在仓库 Settings → Secrets → Actions 中添加上述所有 Secret。

## 8. 多节点扩展路径

当前设计为单 ECS 部署，未来扩展到多台时的迁移步骤：

### 阶段二（3-5 台）
- GitHub Actions 中使用 `strategy.matrix` 循环部署多台 ECS
- 将 MySQL 和 Redis 迁移到阿里云 RDS / Redis 托管服务
- docker-compose 的 `.env` 中修改数据库地址为外部地址

### 阶段三（5 台以上）
- 引入阿里云 ACK（Kubernetes）或自建 K3s
- 使用 Helm Chart 管理
- 引入 Ansible 管理服务器级配置

## 9. 2C4G 低配机注意事项

- **构建不在 ECS 上进行**：所有构建在 GitHub Actions Runner 上完成
- **MySQL 内存**：限制 MySQL 内存使用，在 mysql/conf.d 下添加 `my.cnf` 配置
- **Java 内存**：启动参数限制 JRE 堆内存（`-Xmx512m`）
- **日志清理**：定期清理 Docker 日志和旧镜像
- **监控**：建议用 `docker stats` 或简单脚本监控资源使用

```ini
# mysql/conf.d/my.cnf - 低配优化
[mysqld]
innodb_buffer_pool_size = 256M
max_connections = 50
table_open_cache = 64
```
