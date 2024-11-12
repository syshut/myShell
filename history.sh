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


echo "Package: *
Pin: origin nginx.org
Pin: release o=nginx
Pin-Priority: 900" | sudo tee /etc/apt/preferences.d/99nginx

apt update
apt install -y nginx



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
if [ -z "$DOMAIN" ]; then
  echo "域名不能为空！"
  exit 1
fi

# Step 4: 获取 /etc/nginx/conf.d/default.conf 中的 root 指令内容并替换
DEFAULT_CONF="/etc/nginx/conf.d/default.conf"
NEW_ROOT=$(awk '/location \/ {/,/}/ {if ($1 == "root") print $2}' "$DEFAULT_CONF" | tr -d ';')
# 检查是否成功提取到 root 值
if [ -z "$NEW_ROOT" ]; then
    echo "Error: Could not find 'root' directive in $default_conf"
    exit 1
fi
echo "Extracted root: $NEW_ROOT"

# 使用 sed 替换 grpc.conf 文件中的 root 值
sed -i "s|^\s*root .*;|root $NEW_ROOT;|" "$CONFIG_FILE"

# 确认修改成功
if grep -q "root $NEW_ROOT;" "$CONFIG_FILE"; then
    echo "Updated root directive in $CONFIG_FILE to: $NEW_ROOT"
else
    echo "Error: Failed to update root directive in $CONFIG_FILE"
    exit 1
fi



# Step 5: 修改 ssl_certificate 和 ssl_certificate_key
sudo sed -i "s|ssl_certificate .*|ssl_certificate /usr/local/etc/xray/ssl/${DOMAIN}.fullchain.cer;|" "$CONFIG_FILE"
sudo sed -i "s|ssl_certificate_key .*|ssl_certificate_key /usr/local/etc/xray/ssl/${DOMAIN}.key;|" "$CONFIG_FILE"

# Step 6: 修改 location /你的 ServiceName
read -p "请输入 ServiceName (如 mygrpc): " SERVICE_NAME
sudo sed -i "s|location /你的 ServiceName|location /$SERVICE_NAME|" "$CONFIG_FILE"
