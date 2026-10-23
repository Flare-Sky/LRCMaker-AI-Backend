#!/bin/bash
set -e

# 🛡️ 自动剥离外层未退出的虚拟环境干扰，并引导底层编译工具链
if [ -n "$VIRTUAL_ENV" ]; then
    export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "$VIRTUAL_ENV" \vert{} tr '\n' ':' \vert{} sed 's/:$//')
    unset VIRTUAL_ENV
fi
if [ -d "/Library/Developer/CommandLineTools/usr/bin" ]; then
    export PATH="/Library/Developer/CommandLineTools/usr/bin:$PATH"
fi

# 🛡️ 2. 绕过 /usr/bin 下的 xcrun 空壳替身，并显式指定 macOS SDK 头文件目录 (解决 stdlib.h 找不到的问题)
if [ -d "/Library/Developer/CommandLineTools/usr/bin" ]; then
    export PATH="/Library/Developer/CommandLineTools/usr/bin:$PATH"
fi
if [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" ]; then
    export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
fi

# 🔍 3. 寻找真正的 Universal2 Python 解释器
find_universal_python() {
    for py in /Library/Frameworks/Python.framework/Versions/3.*/bin/python3; do
        if [ -x "$py" ] && file -L "$py" | grep -q "x86_64" && file -L "$py" | grep -q "arm64"; then
            echo "$py"
            return 0
        fi
    done
    return 1
}

echo "================================================="
echo " 🛠️  LRCMaker 虚拟环境无缝切换 & 深度清理工具"
echo "================================================="
echo "请选择你要配置的环境模式："
echo "1. 💻 日常开发模式 (深度清理，并创建单一 venv)"
echo "2. 📦 终极打包模式 (深度清理，并创建 arm64_venv & intel_venv)"
echo "3. 🧹 仅执行深度清理 (斩草除根，不创建新环境)"
read -p "请输入选项 [1, 2 或 3]: " choice

deep_clean() {
    echo ""
    echo "🧹 开始执行深度清理..."
    rm -rf venv arm64_venv intel_venv
    rm -rf build dist *.spec
    rm -f ffmpeg ffprobe ffmpeg.exe ffprobe.exe ffmpeg.zip ffprobe.zip
    rm -f LRCMaker-AI-Backend-*.zip
    find . -type d -name "__pycache__" -exec rm -rf {} + > /dev/null 2>&1 || true
    echo "   ✨ 深度清理完成！你的项目现在比脸还干净。"
}

run_quiet_or_show_error() {
    local log_file="/tmp/lrc_pip_error.log"
    if ! "$@" > "$log_file" 2>&1; then
        echo ""
        echo "❌ 命令执行失败: $*"
        echo "================ 错误日志详情 ================"
        cat "$log_file"
        echo "=============================================="
        rm -f "$log_file"
        exit 1
    fi
    rm -f "$log_file"
}

install_deps() {
    local arch_prefix="$1"
    echo "   - 正在升级 pip ($arch_prefix)..."
    run_quiet_or_show_error $arch_prefix python3 -m pip install --upgrade pip

    # 🌟 核心修复：如果是 x86_64 环境，提前锁定安装拥有预编译二进制 Wheel 的 numba/llvmlite/numpy 版本，防止触发本地源码编译崩溃
    if [[ "$arch_prefix" == *"x86_64"* ]]; then
        echo "   - 正在为 Intel 环境预装底层二进制轮子 (跳过源码编译)..."
        run_quiet_or_show_error $arch_prefix python3 -m pip install --only-binary=:all: "numpy<2.0.0" "llvmlite==0.42.0" "numba==0.59.1"
    fi

    if [ -f "requirements.txt" ]; then
        echo "   - 正在安装 requirements.txt 中的基础依赖 ($arch_prefix)..."
        run_quiet_or_show_error $arch_prefix python3 -m pip install -r requirements.txt
    fi
    echo "   - 正在安装打包及模型库 (pyinstaller, huggingface_hub)..."
    run_quiet_or_show_error $arch_prefix python3 -m pip install pyinstaller huggingface_hub
    echo "   ✅ 依赖安装完成！"
}

if [ "$choice" == "1" ]; then
    deep_clean

    echo ""
    echo "🌱 正在创建日常使用的单一环境 (venv)..."
    arch -arm64 python3 -m venv venv
    
    echo "⏳ 正在拉取并安装依赖，请稍候..."
    source venv/bin/activate
    install_deps "arch -arm64"
    deactivate
    
    echo ""
    echo "🎉 切换成功！当前处于【日常开发模式】"
    echo "👉 运行 'source venv/bin/activate' 即可开始写代码。"

elif [ "$choice" == "2" ]; then
    UNIVERSAL_PY=$(find_universal_python || true)
    if [ -z "$UNIVERSAL_PY" ]; then
        echo ""
        echo "❌ 错误：未检测到官方 Universal2 Python (/Library/Frameworks/Python.framework)！"
        exit 1
    fi
    echo ""
    echo "🔎 已锁定真正的双架构 Python 解释器: $UNIVERSAL_PY"

    deep_clean

    echo ""
    echo "🍎 [1/2] 正在创建 Mac ARM64 专属环境 (arm64_venv)..."
    arch -arm64 "$UNIVERSAL_PY" -m venv arm64_venv
    source arm64_venv/bin/activate
    install_deps "arch -arm64"
    deactivate

    echo "🦋 [2/2] 正在创建 Mac Intel 转译环境 (intel_venv)..."
    arch -x86_64 "$UNIVERSAL_PY" -m venv intel_venv
    source intel_venv/bin/activate
    install_deps "arch -x86_64"
    deactivate
    
    echo ""
    echo "🎉 切换成功！当前处于【终极打包模式】"
    echo "👉 你的项目已就绪，随时可以运行 './deploy.sh' 进行双端打包了！"

elif [ "$choice" == "3" ]; then
    deep_clean
    echo ""
    echo "👋 溜了溜了，项目已恢复至初始纯净状态！"

else
    echo "❌ 无效的选项，请重新运行脚本并输入 1, 2 或 3。"
    exit 1
fi