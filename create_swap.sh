#!/bin/bash

# 检查当前用户是否具有 root 权限
if [[ $EUID -ne 0 ]]; then
   echo "此脚本需要 root 权限，请使用 sudo 运行。" 
   exit 1
fi

# 提示用户输入 swap 大小（单位：MB）
read -p "请输入 swap 大小（单位：MB，例如 1024 表示 1GB）: " SWAP_SIZE

# 确保用户输入的是一个正整数
if ! [[ "$SWAP_SIZE" =~ ^[0-9]+$ ]] || [[ "$SWAP_SIZE" -le 0 ]]; then
   echo "输入无效，请输入一个正整数。"
   exit 1
fi

echo "当前内存和 swap 情况："
free -m

# 停用所有 swap 分区
echo "停用当前所有 swap 分区..."
swapoff -a

# 创建指定大小的 swap 文件
echo "正在创建 ${SWAP_SIZE}MB 的 swap 文件..."
dd if=/dev/zero of=/swap bs=1M count="$SWAP_SIZE" status=progress

# 将新文件格式化为 swap 类型
echo "格式化 swap 文件..."
mkswap /swap

# 启用新 swap 文件
echo "启用 swap 文件..."
swapon /swap

echo "新的内存和 swap 情况："
free -m

echo "swap 文件创建并启用成功。"

# 提示将新 swap 文件添加到 /etc/fstab 中以便开机自动挂载
echo -e "\n要在重启后保持 swap 文件生效，请将以下行添加到 /etc/fstab 中："
echo "/swap none swap sw 0 0"
