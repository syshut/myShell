# 设置虚拟内存
apt install -y sudo curl
curl -O https://raw.githubusercontent.com/syshut/myShell/refs/heads/main/create_swap.sh
chmod +x create_swap.sh && sudo ./create_swap.sh
apt update && apt upgrade -y

# 安装 nginx
# 参见 https://docs.nginx.com/nginx/admin-guide/installing-nginx/installing-nginx-open-source/
sudo apt install curl gnupg2 ca-certificates lsb-release debian-archive-keyring

curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
    | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null

gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
http://nginx.org/packages/mainline/debian `lsb_release -cs` nginx" \
    | sudo tee /etc/apt/sources.list.d/nginx.list


echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" \
    | sudo tee /etc/apt/preferences.d/99nginx

sudo apt update
sudo apt install -y nginx



# 复制 Nginx server 段配置.conf 到 grpc.conf 中。来自：
# https://github.com/XTLS/Xray-examples/blob/main/VLESS-GRPC/server.jsonc
# 修改 server_name、root、ssl_certificate、ssl_certificate_key、location/ 四处



# Step 1: 创建 /etc/nginx/conf.d/grpc.conf 文件
CONFIG_FILE="/etc/nginx/conf.d/grpc.conf"
sudo touch "$CONFIG_FILE"

# Step 2: 下载 README.md 并提取 server {} 块内容到 grpc.conf
curl -sSL https://raw.githubusercontent.com/XTLS/Xray-examples/refs/heads/main/VLESS-GRPC/README.md | \
awk '/server {/,/}/' | sudo tee "$CONFIG_FILE" > /dev/null

# 检查下载是否成功
if [ ! -s "$CONFIG_FILE" ]; then
  echo "下载或提取 server {} 块失败，请检查网络连接。"
  exit 1
fi

# Step 3: 替换 server_name
read -p "请输入域名 (如 example.com): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo "域名不能为空！"
  exit 1
fi

# Step 4: 获取 /etc/nginx/conf.d/default.conf 中的 root 指令内容并替换
DEFAULT_CONF="/etc/nginx/conf.d/default.conf"
ROOT_PATH=$(grep -E '^ *root ' "$DEFAULT_CONF" | awk '{print $2}' | tr -d ';')
if [ -n "$ROOT_PATH" ]; then
  sudo sed -i "s|root .*;|root $ROOT_PATH;|" "$CONFIG_FILE"
else
  echo "未找到 root 指令，跳过替换。"
fi

# Step 5: 修改 ssl_certificate 和 ssl_certificate_key
sudo sed -i "s|ssl_certificate .*|ssl_certificate /usr/local/etc/xray/ssl/${DOMAIN}.fullchain.cer;|" "$CONFIG_FILE"
sudo sed -i "s|ssl_certificate_key .*|ssl_certificate_key /usr/local/etc/xray/ssl/${DOMAIN}.key;|" "$CONFIG_FILE"

# Step 6: 修改 location /你的 ServiceName
read -p "请输入 ServiceName (如 mygrpc): " SERVICE_NAME
sudo sed -i "s|location /你的 ServiceName|location /$SERVICE_NAME|" "$CONFIG_FILE"










# 安装 xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root

# 使用 sed 替换 ExecStart 行
SOURCE_FILE="/etc/systemd/system/xray.service.d/10-donot_touch_single_conf.conf"
TARGET_FILE="/etc/systemd/system/xray.service.d/multi_conf.conf"
if [ -f "$SOURCE_FILE" ]; then
    cp "$SOURCE_FILE" "$TARGET_FILE"
    sed -i 's|ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json|ExecStart=/usr/local/bin/xray run -confdir /usr/local/etc/xray/confs|' "$TARGET_FILE"
else
    echo "源文件不存在：$SOURCE_FILE"
    exit 1
fi


mkdir -p /usr/local/etc/xray/secrets /usr/local/etc/xray/confs

# Step 1: 生成 uuid、key、shortid 到文件
cd /usr/local/etc/xray/secrets || exit
/usr/local/bin/xray uuid > uuid
/usr/local/bin/xray x25519 > key
openssl rand -hex 8 > sid

# 检查文件是否成功生成
if [ ! -s uuid ] || [ ! -s key ] || [ ! -s sid ]; then
  echo "生成 uuid、key 或 sid 失败！"
  exit 1
fi

# 从生成的文件中读取数据
UUID=$(cat uuid)
PRIVATE_KEY=$(grep -oP '(?<=Private key: ).*' key)
SHORTID=$(cat sid)

# Step 2: 下载配置文件
CONFIG_DIR="/usr/local/etc/xray/confs"
mkdir -p "$CONFIG_DIR"
CONFIG_FILE="$CONFIG_DIR/VLESS-gRPC-REALITY.json"

for i in {1..3}; do
    curl -sSL -o "$CONFIG_FILE" "https://raw.githubusercontent.com/XTLS/Xray-examples/refs/heads/main/VLESS-gRPC-REALITY/config_server.jsonc" && break
    echo "尝试重新下载配置文件 ($i/3)..."
    sleep 2
done

if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
    echo "配置文件下载失败！"
    exit 1
fi


# 检查是否下载成功
if [ ! -f "$CONFIG_FILE" ]; then
    echo "配置文件下载失败！"
    exit 1
fi

# 用户输入并验证
read -p "请输入要修改的端口号 (如 12345): " PORT
if ! [[ "$PORT" =~ ^[0-9]{1,5}$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "端口号无效！"
    exit 1
fi

read -p "请输入域名 (如 example.com): " DOMAIN
if ! [[ "$DOMAIN" =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]; then
    echo "域名无效！"
    exit 1
fi

read -p "请输入 serviceName (如 myservice): " SERVICE_NAME
if [[ -z "$SERVICE_NAME" ]]; then
  echo "ServiceName 不能为空！"
  exit 1
fi

# Step 3: 修改配置文件
# 修改 "port" 字段
sed -i "/\"inbounds\":/,/]/s/\"port\": 80/\"port\": $PORT/" "$CONFIG_FILE"

# Step 4: 替换 "id" 字段
sed -i "s/\"id\": \".*\"/\"id\": \"$UUID\"/" "$CONFIG_FILE"

# Step 5: 修改 "dest" 和 "serverNames" 中的域名
sed -i "s/\"dest\": \".*\"/\"dest\": \"$DOMAIN:443\"/" "$CONFIG_FILE"
sed -i "s/\"serverNames\": \[.*\]/\"serverNames\": [\"$DOMAIN\"]/" "$CONFIG_FILE"

# Step 6: 修改 "privateKey"
sed -i "s/\"privateKey\": \".*\"/\"privateKey\": \"$PRIVATE_KEY\"/" "$CONFIG_FILE"

# Step 7: 修改 "shortIds"
sed -i "s/\"shortIds\": \[\".*\"\]/\"shortIds\": [\"$SHORTID\"]/" "$CONFIG_FILE"

# Step 8: 修改 "serviceName"
sed -i "s/\"serviceName\": \"\"/\"serviceName\": \"$SERVICE_NAME\"/" "$CONFIG_FILE"













# 安装 acme.sh
apt update && apt install -y socat
curl https://get.acme.sh | sh -s email=my@example.com
source ~/.acme.sh/acme.sh.env

# 将默认的 zerossl 设置为 lets encrypt
# acme.sh --set-default-ca --server letsencrypt

# 申请证书。多域名 SAN模式，https://github.com/acmesh-official/acme.sh/wiki/How-to-issue-a-cert
if systemctl is-active --quiet nginx; then
  sudo systemctl stop nginx
fi
acme.sh --issue -d "$DOMAIN" --standalone -d "www.$DOMAIN"

mkdir -p /usr/local/etc/xray/ssl
acme.sh --install-cert -d "$DOMAIN" \
  --cert-file /usr/local/etc/xray/ssl/${DOMAIN}.cer \
  --key-file /usr/local/etc/xray/ssl/${DOMAIN}.key \
  --fullchain-file /usr/local/etc/xray/ssl/${DOMAIN}.fullchain.cer \
  --reloadcmd "systemctl restart xray"

if [ ! -f "/usr/local/etc/xray/ssl/${DOMAIN}.cer" ]; then
  echo "证书生成失败！"
  exit 1
fi

systemctl restart nginx && systemctl restart xray

echo "脚本执行完成！"
