#!/bin/bash
set -e

echo "================================================="
echo " 🛠️  LRCMaker 虚拟环境无缝切换 & 深度清理工具"
echo "================================================="
echo "请选择你要配置的环境模式："
echo "1. 💻 日常开发模式 (深度清理，并创建单一 venv)"
echo "2. 📦 终极打包模式 (深度清理，并创建 arm64_venv & intel_venv)"
echo "3. 🧹 仅执行深度清理 (斩草除根，不创建新环境)"
read -p "请输入选项 [1, 2 或 3]: " choice

# 💥 核心：深度清理函数
deep_clean() {
    echo ""
    echo "🧹 开始执行深度清理..."
    
    echo "   - 清理虚拟环境 (venv, arm64_venv, intel_venv)..."
    rm -rf venv arm64_venv intel_venv

    echo "   - 清理 PyInstaller 构建产物 (build, dist, *.spec)..."
    rm -rf build dist *.spec

    echo "   - 清理请来的“大佛” (ffmpeg, ffprobe 二进制文件)..."
    rm -f ffmpeg ffprobe ffmpeg.exe ffprobe.exe

    echo "   - 清理打包生成的安装包残留 (*.zip)..."
    rm -f LRCMaker-AI-Backend-*.zip

    echo "   - 清理 Python 运行缓存 (__pycache__)..."
    # 递归查找并删除当前目录下所有的 __pycache__ 文件夹
    find . -type d -name "__pycache__" -exec rm -rf {} + > /dev/null 2>&1 || true

    echo "   ✨ 深度清理完成！你的项目现在比脸还干净。"
}

# 📦 复用：依赖安装函数
install_deps() {
    echo "   - 正在升级 pip..."
    pip install --upgrade pip > /dev/null 2>&1
    if [ -f "requirements.txt" ]; then
        echo "   - 正在安装 requirements.txt 中的基础依赖..."
        pip install -r requirements.txt > /dev/null 2>&1
    fi
    echo "   - 正在安装打包及模型库 (pyinstaller, huggingface_hub)..."
    pip install pyinstaller huggingface_hub > /dev/null 2>&1
    echo "   ✅ 依赖安装完成！"
}

# 🚀 路由：根据选项执行动作
if [ "$choice" == "1" ]; then
    deep_clean

    echo ""
    echo "🌱 正在创建日常使用的单一环境 (venv)..."
    arch -arm64 python3 -m venv venv
    
    echo "⏳ 正在拉取并安装依赖，请稍候..."
    source venv/bin/activate
    install_deps
    deactivate
    
    echo ""
    echo "🎉 切换成功！当前处于【日常开发模式】"
    echo "👉 运行 'source venv/bin/activate' 即可开始写代码。"

elif [ "$choice" == "2" ]; then
    deep_clean

    echo ""
    echo "🍎 [1/2] 正在创建 Mac ARM64 专属环境 (arm64_venv)..."
    arch -arm64 python3 -m venv arm64_venv
    source arm64_venv/bin/activate
    install_deps
    deactivate

    echo "🦋 [2/2] 正在创建 Mac Intel 转译环境 (intel_venv)..."
    arch -x86_64 python3 -m venv intel_venv
    source intel_venv/bin/activate
    install_deps
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