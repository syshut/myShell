#!/bin/bash

# 设置虚拟内存
curl -O https://raw.githubusercontent.com/syshut/myShell/refs/heads/main/create_swap.sh
chmod +x create_swap.sh && sudo ./create_swap.sh
apt update && apt upgrade -y

# 检查 jq 是否安装，如果没有安装，则进行安装
if ! command -v jq &> /dev/null; then
	echo "jq 未安装，正在安装 jq..."
	sudo apt install -y jq
fi

# 安装 xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root

XRAY_CONFIG_DIR="/usr/local/etc/xray/confs"
mkdir -p /usr/local/etc/xray/secrets ${XRAY_CONFIG_DIR}

# 使用 sed 替换 ExecStart 行
SOURCE_FILE="/etc/systemd/system/xray.service.d/10-donot_touch_single_conf.conf"
TARGET_FILE="/etc/systemd/system/xray.service.d/multi_conf.conf"
if [ -f "$SOURCE_FILE" ]; then
	cp "$SOURCE_FILE" "$TARGET_FILE"
	sed -i "s|ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json|ExecStart=/usr/local/bin/xray run -confdir $XRAY_CONFIG_DIR|" "$TARGET_FILE"
else
	echo "源文件不存在：$SOURCE_FILE"
	exit 1
fi

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
PRIVATE_KEY=$(awk -F ': ' '/Private key/ {print $2}' key)
PUBLIC_KEY=$(awk -F ': ' '/Public key/ {print $2}' key)
SHORTID=$(cat sid)

# Step 2: 下载配置文件
CONFIG_FILE="$XRAY_CONFIG_DIR/VLESS-gRPC-REALITY.json"

for i in {1..3}; do
	curl -sSL -o "$CONFIG_FILE" "https://raw.githubusercontent.com/XTLS/Xray-examples/refs/heads/main/VLESS-gRPC-REALITY/config_server.jsonc" && break
	echo "尝试重新下载配置文件 ($i/3)..."
	sleep 2
done

if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
	echo "配置文件下载失败！"
	exit 1
fi

# 用户选择是否偷自己
echo "请选择是否偷自己（输入1选择偷自己，输入2选择偷别人）"
read -p "请输入选择（1/2）: " CHOICE
if [ "$CHOICE" -eq 1 ]; then
	echo "您选择了偷自己"
	read -p "请输入您的自有域名 (如 example.com): " DOMAIN
	if [ -z "$DOMAIN" ]; then
		echo "Domain 不能为空！"
		exit 1
	fi
else
	echo "您选择了偷别人"
	read -p "请输入 dest 伪装域名 (如 www.uclahealth.org): " DOMAIN
	if [ -z "$DOMAIN" ]; then
		echo "dest 不能为空！"
		exit 1
	fi
fi

read -p "请输入别名: " REMARKS

read -p "请输入要修改的端口号 (如 8443，不要443): " PORT

# 验证输入是否为1到5位的数字，并且在1到65535之间
if ! [[ "$PORT" =~ ^[1-9][0-9]{0,4}$ ]] || [ "$PORT" -gt 65535 ]; then
	echo "端口号无效！"
	exit 1
fi

read -p "请输入 serviceName (如 grpc): " SERVICE_NAME
if [ -z "$SERVICE_NAME" ]; then
	echo "serviceName 不能为空！"
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
sed -i "s|\"privateKey\": \".*\"|\"privateKey\": \"$PRIVATE_KEY\"|" "$CONFIG_FILE"

# Step 7: 修改 "shortIds"
sed -i "s/\"shortIds\": \[\".*\"\]/\"shortIds\": [\"$SHORTID\"]/" "$CONFIG_FILE"

# Step 8: 修改 "serviceName"
sed -i "s/\"serviceName\": \"\"/\"serviceName\": \"$SERVICE_NAME\"/" "$CONFIG_FILE"

# Step 9: 拆分配置文件，生成不同部分的单独文件
echo "正在拆分配置文件..."
for FIELD in log routing inbounds outbounds policy; do
	OUTPUT_FILE="${XRAY_CONFIG_DIR}/${FIELD}.json"
		
	# 对于对象类型（如 log、routing、policy），保留最外层的大括号
	if [ "$FIELD" == "log" ] || [ "$FIELD" == "routing" ] || [ "$FIELD" == "policy" ]; then
		jq ". | {${FIELD}: .${FIELD}}" "$CONFIG_FILE" > "$OUTPUT_FILE"
	# 对于数组类型（如 inbounds、outbounds），保留父级包裹结构
	elif [ "$FIELD" == "inbounds" ] || [ "$FIELD" == "outbounds" ]; then
		jq ". | {${FIELD}: .${FIELD}}" "$CONFIG_FILE" > "$OUTPUT_FILE"
	fi

	# 确保文件生成成功
	if [ ! -s "$OUTPUT_FILE" ]; then
		echo "拆分文件失败：$OUTPUT_FILE"
		exit 1
	fi

	echo "已生成拆分文件：$OUTPUT_FILE"
done

# 删除原始配置文件，因为已拆分
rm -f "$CONFIG_FILE"

# 重载并重启服务
systemctl daemon-reload
if systemctl restart xray; then
	echo "Xray 服务已成功重启"
else
	echo "Xray 服务重启失败"
	systemctl status xray
	exit 1
fi

# 如果选择偷自己，则安装 nginx 和申请 ssl 证书
if [ "$CHOICE" -eq 1 ]; then
	# 安装 nginx
	# 参见 https://docs.nginx.com/nginx/admin-guide/installing-nginx/installing-nginx-open-source/
	sudo apt install -y curl gnupg2 ca-certificates lsb-release debian-archive-keyring

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


	# 安装 acme.sh
	apt update && apt install -y socat
	curl https://get.acme.sh | sh -s email=my@example.com


	# 将默认的 zerossl 设置为 lets encrypt
	# /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt

	# 申请证书。多域名 SAN模式，https://github.com/acmesh-official/acme.sh/wiki/How-to-issue-a-cert
	if systemctl is-active --quiet nginx; then
		sudo systemctl stop nginx
	fi
	/root/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone -d "www.$DOMAIN"

	mkdir -p /usr/local/etc/xray/ssl
	/root/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
		--cert-file /usr/local/etc/xray/ssl/${DOMAIN}.cer \
		--key-file /usr/local/etc/xray/ssl/${DOMAIN}.key \
		--fullchain-file /usr/local/etc/xray/ssl/${DOMAIN}.fullchain.cer \
		--reloadcmd "systemctl restart xray"

	if [ ! -f "/usr/local/etc/xray/ssl/${DOMAIN}.cer" ]; then
		echo "证书生成失败！"
		exit 1
	fi


	# Step 1: 创建 /etc/nginx/conf.d/reality.conf 文件
	NGINX_CONFIG_FILE="/etc/nginx/conf.d/reality.conf"
	sudo touch "$NGINX_CONFIG_FILE"


	# 下载文件并提取配置
	wget -q https://raw.githubusercontent.com/XTLS/Xray-examples/refs/heads/main/VLESS-GRPC/README.md -O - | \
		awk '/^server \{/ {f=1} f; /^\}/ {print; f=0}' | \
		sed '/# 在 location 后填写/,/^\}/d' | \
		sed '/^#/d' > /etc/nginx/conf.d/reality.conf
	
	# 验证配置是否已正确写入
	if grep -q "server {" /etc/nginx/conf.d/reality.conf; then
		echo "Successfully updated /etc/nginx/conf.d/reality.conf with the new server block."
	else
		echo "Error: Failed to update /etc/nginx/conf.d/reality.conf."
		exit 1
	fi

	# Step 3: 替换 server_name
	sudo sed -i "s|server_name .*|server_name ${DOMAIN};|" "$NGINX_CONFIG_FILE"

	# Step 4: 获取 /etc/nginx/conf.d/default.conf 中的 root 指令内容并替换
	DEFAULT_CONF="/etc/nginx/conf.d/default.conf"
	NEW_ROOT=$(awk '/location \/ {/,/}/ {if ($1 == "root") print $2}' "$DEFAULT_CONF" | tr -d ';')
	# 检查是否成功提取到 root 值
	if [ -z "$NEW_ROOT" ]; then
		echo "Error: Could not find 'root' directive in $default_conf"
		exit 1
	fi
	echo "Extracted root: $NEW_ROOT"
	
	# 使用 sed 替换 reality.conf 文件中的 root 值
	sed -i "s|^\(\s*\)root .*;|\1root $NEW_ROOT;|" "$NGINX_CONFIG_FILE"
	
	# 确认修改成功
	if grep -q "root $NEW_ROOT;" "$NGINX_CONFIG_FILE"; then
		echo "Updated root directive in $NGINX_CONFIG_FILE to: $NEW_ROOT"
	else
		echo "Error: Failed to update root directive in $NGINX_CONFIG_FILE"
		exit 1
	fi
	
	# Step 5: 修改 ssl_certificate 和 ssl_certificate_key
	sudo sed -i "s|ssl_certificate .*|ssl_certificate /usr/local/etc/xray/ssl/${DOMAIN}.fullchain.cer;|" "$NGINX_CONFIG_FILE"
	sudo sed -i "s|ssl_certificate_key .*|ssl_certificate_key /usr/local/etc/xray/ssl/${DOMAIN}.key;|" "$NGINX_CONFIG_FILE"


	systemctl restart nginx && systemctl restart xray
fi

# 输出分享链接
IP=$(curl -s https://api.ipify.org || curl -s https://icanhazip.com)

echo "分享链接：vless://$UUID@$IP:$PORT?encryption=none&security=reality&sni=$DOMAIN&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORTID&type=grpc&authority=$DOMAIN&serviceName=$SERVICE_NAME&mode=gun#$REMARKS"
