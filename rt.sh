#!/bin/bash

# 设置虚拟内存
curl -O https://raw.githubusercontent.com/syshut/myShell/refs/heads/main/create_swap.sh
chmod +x create_swap.sh && sudo ./create_swap.sh
apt update && apt upgrade -y

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

# 用户输入并验证
read -p "请输入要修改的端口号 (如 8443，不要443): " PORT

# 验证输入是否为1到5位的数字，并且在1到65535之间
if ! [[ "$PORT" =~ ^[1-9][0-9]{0,4}$ ]] || [ "$PORT" -gt 65535 ]; then
    echo "端口号无效！"
    exit 1
fi

read -p "请输入 dest (如 www.uclahealth.org): " DEST
if [ -z "$DEST" ]; then
  echo "dest 不能为空！"
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
sed -i "s/\"dest\": \".*\"/\"dest\": \"$DEST:443\"/" "$CONFIG_FILE"
sed -i "s/\"serverNames\": \[.*\]/\"serverNames\": [\"$DEST\"]/" "$CONFIG_FILE"

# Step 6: 修改 "privateKey"
sed -i "s|\"privateKey\": \".*\"|\"privateKey\": \"$PRIVATE_KEY\"|" "$CONFIG_FILE"

# Step 7: 修改 "shortIds"
sed -i "s/\"shortIds\": \[\".*\"\]/\"shortIds\": [\"$SHORTID\"]/" "$CONFIG_FILE"

# Step 8: 修改 "serviceName"
sed -i "s/\"serviceName\": \"\"/\"serviceName\": \"$SERVICE_NAME\"/" "$CONFIG_FILE"

systemctl daemon-reload
if systemctl restart xray; then
    echo "Xray 服务已成功重启"
else
    echo "Xray 服务重启失败"
    systemctl status xray
    exit 1
fi

IP=$(curl -s https://api.ipify.org || curl -s https://icanhazip.com)

echo "分享链接：vless://$UUID@$IP:$PORT?encryption=none&security=reality&sni=$DEST&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORTID&type=grpc&authority=$DEST&serviceName=$SERVICE_NAME&mode=gun#test
"