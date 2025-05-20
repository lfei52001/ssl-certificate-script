#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 权限运行此脚本"
  exit 1
fi

# 提示用户输入邮箱，设置默认值
echo "请输入用于 Let's Encrypt 通知的邮箱地址（默认：lfei52001@gmail.com）:"
read -r -p "" EMAIL
EMAIL=${EMAIL:-lfei52001@gmail.com}

# 验证邮箱是否为空
if [ -z "$EMAIL" ]; then
  echo "错误：邮箱不能为空"
  exit 1
fi

# 验证邮箱格式
if ! echo "$EMAIL" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
  echo "错误：无效的邮箱格式，请输入有效的邮箱地址"
  exit 1
fi

# 提示用户输入域名（支持多个，逗号分隔）
echo "请输入要申请证书的域名（多个域名用逗号分隔，例如：example.com,sub.example.com）:"
read -r DOMAIN_INPUT

# 验证域名输入是否为空
if [ -z "$DOMAIN_INPUT" ]; then
  echo "错误：域名不能为空"
  exit 1
fi

# 将输入的域名分割为数组
IFS=',' read -r -a DOMAIN_ARRAY <<< "$DOMAIN_INPUT"

# 验证每个域名格式并构建 Certbot 域名参数
CERTBOT_DOMAINS=""
PRIMARY_DOMAIN=""
for d in "${DOMAIN_ARRAY[@]}"; do
  d=$(echo "$d" | xargs) # 去除前后空格
  if [ -z "$d" ]; then
    echo "错误：域名列表中包含空值"
    exit 1
  fi
  if ! echo "$d" | grep -qE '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
    echo "错误：无效的域名格式：$d"
    exit 1
  fi
  CERTBOT_DOMAINS="$CERTBOT_DOMAINS -d $d"
  if [ -z "$PRIMARY_DOMAIN" ]; then
    PRIMARY_DOMAIN="$d" # 将第一个域名作为主域名用于证书路径
  fi
done

# 定义证书路径（使用第一个域名）
CERT_PATH="/etc/letsencrypt/live/$PRIMARY_DOMAIN"

# 更新系统并安装必要软件
echo "更新系统并安装 Certbot..."
apt update && apt upgrade -y
apt install certbot -y

# 停止可能占用 80 端口的服务（可选，根据需要调整）
systemctl stop apache2 2>/dev/null || true

# 使用 standalone 模式申请证书
echo "为以下域名申请 SSL 证书：${DOMAIN_ARRAY[*]}..."
eval certbot certonly --standalone \
  --non-interactive \
  --agree-tos \
  --email "$EMAIL" \
  $CERTBOT_DOMAINS \
  --http-01-port 80

# 检查证书是否申请成功
if [ -d "$CERT_PATH" ]; then
  echo "证书申请成功！证书路径：$CERT_PATH"
else
  echo "证书申请失败，请检查错误信息"
  exit 1
fi

# 测试自动续签
echo "测试证书自动续签..."
certbot renew --dry-run

# 配置自动续签（Cron 任务）
CRON_JOB="0 3 * * * /usr/bin/certbot renew --quiet --no-self-upgrade"
CRON_FILE="/etc/cron.d/certbot-renew"
echo "配置自动续签任务..."
echo "$CRON_JOB" > "$CRON_FILE"
chmod 644 "$CRON_FILE"

# 验证 Cron 任务
if [ -f "$CRON_FILE" ]; then
  echo "自动续签任务已配置，每天 3:00 执行"
else
  echo "自动续签任务配置失败"
  exit 1
fi

echo "脚本执行完成！SSL 证书已为 ${DOMAIN_ARRAY[*]} 申请并配置自动续签。"