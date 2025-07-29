# 第一阶段：构建依赖 (使用更小的基础镜像)
FROM python:3.9-alpine AS builder

WORKDIR /app

# 一次性完成所有系统配置和依赖安装
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories \
    && apk add --no-cache --virtual .build-deps gcc musl-dev libffi-dev

# 配置pip并使用单次命令完成所有包安装
RUN pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple \
    && pip install --no-cache-dir wheel

COPY requirements.txt .
RUN pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt && \
    apk del .build-deps  # 删除编译依赖

# 第二阶段：运行环境 (使用相同基础镜像)
FROM python:3.9-alpine

WORKDIR /app

# 一次性设置环境变量、时区和依赖
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TZ=Asia/Shanghai

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories && \
    apk add --no-cache libffi tzdata nginx supervisor && \
    cp /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    mkdir -p /run/nginx /app/app/{data,backups,uploads,static} /data && \
    rm -rf /var/cache/apk/*

# 复制并安装wheel后立即删除
COPY --from=builder /wheels /wheels
RUN pip install --no-cache-dir /wheels/* && rm -rf /wheels

# 集中复制配置文件
COPY docker/nginx.conf /defaults/nginx.conf
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# 合并权限设置
COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/cleanup_backups.sh /app/docker/cleanup_backups.sh
RUN chmod +x /entrypoint.sh /app/docker/cleanup_backups.sh

# 最后复制应用代码
COPY . .

VOLUME ["/data", "/app/app/backups", "/app/app/uploads", "/app/app/static", "/etc/nginx/http.d"]
EXPOSE 80
ENTRYPOINT ["/entrypoint.sh"]