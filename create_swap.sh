#!/bin/bash

# 检查当前用户是否具有 root 权限
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[31m此脚本需要 root 权限，请使用 sudo 运行。\033[0m"
    exit 1
fi

# 输出当前服务器的内存和 swap 使用情况（以 MB 为单位）
echo -e "\n\033[34m当前服务器的内存和 swap 情况（单位：MB）：\033[0m"
free -m

# 输出总物理内存大小（以 MB 为单位）
TOTAL_MEM=$(free -m | awk '/^Mem:/ {print $2}')
echo -e "\033[34m总内存大小：${TOTAL_MEM}MB\033[0m"

# 输出总 swap 大小（以 MB 为单位）
TOTAL_SWAP=$(free -m | awk '/^Swap:/ {print $2}')
echo -e "\033[34m当前 swap 大小：${TOTAL_SWAP}MB\033[0m\n"

# 提示用户输入 swap 大小（单位：MB）
read -p "请输入 swap 大小（单位：MB，例如 1024 表示 1GB）: " SWAP_SIZE

# 确保用户输入的是一个正整数
if ! [[ "$SWAP_SIZE" =~ ^[0-9]+$ ]] || [[ "$SWAP_SIZE" -le 0 ]]; then
    echo -e "\033[31m输入无效，请输入一个正整数。\033[0m"
    exit 1
fi

# 检查磁盘空间是否足够（以 MB 为单位）
AVAILABLE_SPACE=$(df / --output=avail -m | tail -1)
if [[ "$AVAILABLE_SPACE" -le "$SWAP_SIZE" ]]; then
    echo -e "\033[31m磁盘空间不足，无法创建 ${SWAP_SIZE}MB 的 swap 文件。\033[0m"
    exit 1
fi

echo -e "\n\033[34m当前内存和 swap 情况（单位：MB）：\033[0m"
free -m

# 停用所有 swap 分区
echo -e "\033[33m停用当前所有 swap 分区...\033[0m"
swapoff -a

# 检查 /swap 文件是否已存在
if [[ -f /swap ]]; then
    echo -e "\033[33m检测到已有 /swap 文件，正在删除...\033[0m"
    rm -f /swap
fi

# 创建指定大小的 swap 文件
echo -e "\033[33m正在创建 ${SWAP_SIZE}MB 的 swap 文件...\033[0m"
if ! dd if=/dev/zero of=/swap bs=1M count="$SWAP_SIZE" status=progress; then
    echo -e "\033[31m创建 swap 文件失败。\033[0m"
    exit 1
fi

# 设置文件权限
chmod 600 /swap

# 将新文件格式化为 swap 类型
echo -e "\033[33m格式化 swap 文件...\033[0m"
if ! mkswap /swap; then
    echo -e "\033[31m格式化 swap 文件失败。\033[0m"
    rm -f /swap
    exit 1
fi

# 启用新 swap 文件
echo -e "\033[33m启用 swap 文件...\033[0m"
if ! swapon /swap; then
    echo -e "\033[31m启用 swap 文件失败。\033[0m"
    rm -f /swap
    exit 1
fi

echo -e "\n\033[34m新的内存和 swap 情况（单位：MB）：\033[0m"
free -m

echo -e "\n\033[32mswap 文件创建并启用成功。\033[0m"

# 提示将新 swap 文件添加到 /etc/fstab 中以便开机自动挂载
echo -e "\n\033[36m要在重启后保持 swap 文件生效，请将以下行添加到 /etc/fstab 中：\033[0m"
echo -e "\033[33m/swap none swap sw 0 0\033[0m"

exit 0
