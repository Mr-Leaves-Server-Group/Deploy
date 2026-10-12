# ============================================================
# 基于官方 pterodactylchina/panel:latest 的自定义镜像
#
# 思路：官方镜像已含编译好的 1.15.0 运行时（PHP8.3 / nginx / supervisord /
#       entrypoint / 已编译前端），我们只需叠加编译后的前端资源
#       （模组包一键安装页 + 侧边栏改版）。
#   好处：不用每次重跑 composer / 装 PHP 扩展 / apk add，构建快、运行时与官方一致。
#   数据库相关保持官方默认，不做任何改动。
# ============================================================

# ---- 阶段 0：编译我们修改过的前端 ----
FROM node:22-alpine AS frontend
WORKDIR /app
COPY . ./
RUN yarn install --frozen-lockfile \
    && yarn run build:production

# ---- 阶段 1：以官方镜像为底座，只叠加前端资源 ----
FROM pterodactylchina/panel:latest

# 覆盖编译后的前端资源（含模组包页面、侧边栏改版、数据库隐藏等）
COPY --from=frontend /app/public/assets ./public/assets

# 覆盖后端 PHP 改动（模组包本地化接口 + egg 变量自动同步）：
# 官方镜像内置的是未含这些改动的旧代码，必须把改动的控制器/路由/config 覆盖进去，
# 否则运行时路由 /api/client/modpacks 会报 "route could not be found"。
COPY app/Http/Controllers/Api/Client/ModpackController.php app/Http/Controllers/Api/Client/ModpackController.php
COPY app/Http/Controllers/Base/ModpackSyncController.php app/Http/Controllers/Base/ModpackSyncController.php
COPY app/Services/Modpacks/ModpackEggSyncService.php app/Services/Modpacks/ModpackEggSyncService.php
COPY app/Console/Commands/Overrides/ModpackSyncEggCommand.php app/Console/Commands/Overrides/ModpackSyncEggCommand.php
COPY routes/api-client.php routes/api-client.php
COPY routes/base.php routes/base.php
COPY config/pterodactyl.php config/pterodactyl.php

# 覆盖容器启动脚本与 nginx 模板：
# 官方镜像内置的是官方旧版 entrypoint（含 certbot 调用），必须用我们修改后的版本替换，
# 否则启动时仍会调用已被卸载的 certbot 并报 "certbot: not found"，证书检查也不会执行。
COPY .github/docker/entrypoint.sh .github/docker/entrypoint.sh
COPY .github/docker/default.conf .github/docker/default.conf
COPY .github/docker/default_ssl.conf .github/docker/default_ssl.conf

# 移除容器内 certbot（证书由宿主机宝塔签发并自动续期、映射进容器，容器内不再需要申请/续期）
# 同时清掉官方镜像内置的每天 23:00 certbot renew 定时任务
# 连接带自签/不受信证书的 MySQL 时跳过服务器证书校验
# （否则 schema 导入会报 "certificate is NOT trusted"）。
# 用 MariaDB 客户端认的 ssl-verify-server-cert=0；不能用 ssl-mode（MariaDB 不认，会报 unknown variable 中止）。
RUN apk del certbot certbot-nginx \
    && sed -i '/certbot/d' /var/spool/cron/crontabs/root \
    && mkdir -p /root && printf '[client]\nssl-verify-server-cert=0\n' > /root/.my.cnf \
    && mkdir -p /app/storage/modpacks/logos \
    # 清掉可能存在的路由/配置缓存，确保新路由与 config 改动生效
    && (php artisan optimize:clear 2>/dev/null || true)
