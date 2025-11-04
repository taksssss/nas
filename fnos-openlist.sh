#!/bin/bash
#
# @file fnos-openlist.sh
# @brief 飞牛OS OpenList 管理脚本
#
# 该脚本提供 OpenList 的安装、升级、管理和信息查看功能，
# 支持自动检测平台和架构，选择 lite 或完整版，
# 包含菜单交互和常用操作的快捷执行。
#
# 作者: Tak
# GitHub: https://github.com/taksssss/nas
#

# ===============================
# 配置
# ===============================
REPO_OWNER="OpenListTeam"
REPO_NAME="OpenList"

BIN_NAME="alist"
TMP_TAR="openlist-latest.tar.gz"

# 为管道执行交互，read 从 /dev/tty 读取
INPUT_DEV="/dev/tty"

# ===============================
# 用户选择 GitHub 下载方式
# ===============================
echo "请选择 GitHub 下载方式："
echo "1) 官方直连"
echo "2) gh-proxy.com 镜像加速"
read -p "输入选项 [1-2]（默认 1）： " choice < $INPUT_DEV

case "$choice" in
    2)
        echo "使用 gh-proxy.com 镜像加速"
        GITHUB_API="https://gh-proxy.com/https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}"
        GITHUB_RELEASE="https://gh-proxy.com/https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download"
        ;;
    *)
        echo "使用 GitHub 官方直连"
        GITHUB_API="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}"
        GITHUB_RELEASE="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download"
        ;;
esac

# ===============================
# 自动识别平台和架构
# ===============================
UNAME_OUT=$(uname -s)
UNAME_ARCH=$(uname -m)

# 默认非 lite
LITE=false
read -p "是否下载 lite 版本？[y/N] (默认 N): " lite_choice < $INPUT_DEV
[[ "$lite_choice" =~ ^[Yy]$ ]] && LITE=true

case "$UNAME_OUT" in
    Linux) PLATFORM="linux" ;;
    Darwin) PLATFORM="darwin" ;;
    FreeBSD) PLATFORM="freebsd" ;;
    WindowsNT|MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
    Android) PLATFORM="android" ;;
    *) echo "❌ 不支持的平台：$UNAME_OUT"; exit 1 ;;
esac

case "$UNAME_ARCH" in
    x86_64) ARCH="amd64" ;;
    i386|i686) ARCH="386" ;;
    armv5*|armv6*|armv7*|armv7l) ARCH="arm" ;;
    aarch64) ARCH="arm64" ;;
    loongarch64) ARCH="loong64" ;;
    mips) ARCH="mips" ;;
    mips64) ARCH="mips64" ;;
    mips64el|mips64le) ARCH="mips64le" ;;
    mipsel) ARCH="mipsle" ;;
    ppc64le) ARCH="ppc64le" ;;
    riscv64) ARCH="riscv64" ;;
    s390x) ARCH="s390x" ;;
    *) echo "❌ 不支持的架构：$UNAME_ARCH"; exit 1 ;;
esac

echo "检测到平台：$PLATFORM，架构：$ARCH"

# ===============================
# 自动检测 alist 可执行文件路径
# ===============================
EXISTING_PROC=$(ps -ef | grep "[a]list server" | awk '{print $8}' | head -n1)

if [ -n "$EXISTING_PROC" ]; then
    BIN_PATH="$EXISTING_PROC"
    BIN_DIR=$(dirname "$BIN_PATH")
    echo "检测到运行中的 alist：$BIN_PATH"
else
    # 没有运行中的进程，则查找 @appcenter 下的 alist 可执行文件
    BIN_PATH=$(find / -type f -path "*/@appcenter/alist3/bin/alist" 2>/dev/null | head -n1)
    if [ -n "$BIN_PATH" ]; then
        BIN_DIR=$(dirname "$BIN_PATH")
        echo "找到 alist 可执行文件：$BIN_PATH"
    else
        echo "❌ 未找到 alist 可执行文件，请确认安装路径"
        exit 1
    fi
fi

# ===============================
# 数据目录使用 BIN_DIR 的父目录
# ===============================
DATA_DIR=$(dirname "$BIN_DIR")
echo "使用数据目录：$DATA_DIR"

# ===============================
# 获取本地版本
# ===============================
if [ -x "$BIN_PATH" ]; then
    LOCAL_VERSION=$($BIN_PATH version 2>/dev/null | grep -E '^Version:' | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')
    [ -z "$LOCAL_VERSION" ] && LOCAL_VERSION=$($BIN_PATH version 2>/dev/null | grep -E '^WebVersion:' | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')
else
    echo "⚠️ 未找到 alist 可执行文件，将进行全新安装"
    LOCAL_VERSION="0.0.0"
fi
echo "本地版本：$LOCAL_VERSION"

# ===============================
# 获取最新版本
# ===============================
LATEST_VERSION=$(curl -s $GITHUB_API/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/^v//')
if [ -z "$LATEST_VERSION" ]; then
    echo "❌ 无法获取最新版本"
    exit 1
fi
echo "最新版本：$LATEST_VERSION"

# ===============================
# 判断是否更新或重启
# ===============================
if [ "$LOCAL_VERSION" = "$LATEST_VERSION" ]; then
    echo "✅ 已是最新版本"
    read -p "是否重启 alist 服务？[y/N] (默认 N): " restart_choice < $INPUT_DEV
    [[ "$restart_choice" =~ ^[Yy]$ ]] && RESTART=true || RESTART=false
else
    echo "⬆️ 发现新版本：$LATEST_VERSION，开始升级..."
    RESTART=true

    # ===============================
    # 构建下载包名
    # ===============================
    PACKAGE_NAME="openlist-${PLATFORM}-${ARCH}.tar.gz"
    $LITE && PACKAGE_NAME="openlist-${PLATFORM}-${ARCH}-lite.tar.gz"
    DOWNLOAD_URL="$GITHUB_RELEASE/v$LATEST_VERSION/$PACKAGE_NAME"

    # ===============================
    # 下载最新版本
    # ===============================
    TMP_TAR="$BIN_DIR/$TMP_TAR"
    echo "下载 $DOWNLOAD_URL ..."
    curl -L -o "$TMP_TAR" "$DOWNLOAD_URL"
    if [ $? -ne 0 ]; then
        echo "❌ 下载失败"
        exit 1
    fi

    # ===============================
    # 解压覆盖
    # ===============================
    echo "解压并覆盖旧版本..."
    tar -xzf "$TMP_TAR" -C "$BIN_DIR"
    if [ $? -ne 0 ]; then
        echo "❌ 解压失败"
        exit 1
    fi

    mv -f "$BIN_DIR/openlist" "$BIN_PATH"
    chmod +x "$BIN_PATH"
    rm "$TMP_TAR"
fi

# ===============================
# 杀掉旧进程并启动新进程（尝试 sudo）
# ===============================
PIDS=$(pgrep -f "$BIN_PATH server")
if [ -n "$PIDS" ]; then
    echo "尝试停止旧 alist 进程..."
    sudo kill $PIDS 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "⚠️ 无法杀掉旧进程，请检查权限"
    else
        sleep 2
        echo "旧进程已停止"
    fi
else
    echo "没有检测到旧 alist 进程"
fi

if [ "$RESTART" = true ]; then
    echo "启动 alist 服务..."
    sudo nohup "$BIN_PATH" server --data "$DATA_DIR" >/dev/null 2>&1 &
fi

echo "✅ 升级完成！当前版本：$LATEST_VERSION"
