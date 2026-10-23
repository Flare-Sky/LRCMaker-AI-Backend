#!/bin/bash
set -e

if [ -n "$VIRTUAL_ENV" ]; then
    export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "$VIRTUAL_ENV" | tr '\n' ':' | sed 's/:$//')
    unset VIRTUAL_ENV
fi
if [ -d "/Library/Developer/CommandLineTools/usr/bin" ]; then
    export PATH="/Library/Developer/CommandLineTools/usr/bin:$PATH"
fi
if [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" ]; then
    export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
fi

echo "================================================="
echo " 🚀 LRCMaker AI 跨平台一键部署与同步脚本 (v2.2 终极融合版)"
echo "================================================="
echo "请选择你要执行的操作："
echo "1. 📥 从 GitHub 同步最新代码到本地 (Git Pull)"
echo "2. 📦 完整发布流程 (提交代码 -> 本地 Mac 打包 -> 云端 Win 打包)"
read -p "请输入选项 [1 或 2]: " choice

download_ffmpeg() {
    local target_arch="$1"
    echo "📥 正在拉取 Mac ($target_arch) 专属静态版 FFmpeg 与 FFprobe..."
    rm -f ffmpeg ffprobe ffmpeg.zip ffprobe.zip
    curl -sL "https://ffmpeg.martin-riedl.de/redirect/latest/macos/${target_arch}/release/ffmpeg.zip" -o ffmpeg.zip
    curl -sL "https://ffmpeg.martin-riedl.de/redirect/latest/macos/${target_arch}/release/ffprobe.zip" -o ffprobe.zip
    unzip -o -q ffmpeg.zip && unzip -o -q ffprobe.zip
    chmod +x ffmpeg ffprobe
    xattr -c ffmpeg ffprobe 2>/dev/null || true
    rm -f ffmpeg.zip ffprobe.zip
    echo "✅ FFmpeg ($target_arch) 准备就绪！"
}

if [ "$choice" == "1" ]; then
    echo "👉 正在拉取云端代码..."
    git pull || { echo "❌ 同步失败！请检查是否有网络问题或代码冲突。"; exit 1; }
    echo "✅ 同步完成！"
    exit 0
elif [ "$choice" == "2" ]; then
    read -p "👉 请输入新版本号 (例如 2.2, 不需要输入v): " version
    full_version="v$version"
    arm64_zip_name="LRCMaker-AI-Backend-Mac-Arm64-$full_version.zip"
    intel_zip_name="LRCMaker-AI-Backend-Mac-Intel-$full_version.zip"
    mac_zip_name="LRCMaker-AI-Backend-Mac-$full_version.zip"

    echo ""
    echo "⚙️ 步骤 1/5: 提交并推送代码到 GitHub..."
    git add .
    read -p "请输入本次更新的 Commit 描述 (直接回车默认使用 'Release $full_version'): " commit_msg
    if [ -z "$commit_msg" ]; then
        commit_msg="Release $full_version"
    fi
    
    if git diff --cached --quiet; then
        echo "⚠️ 没有检测到需要 commit 的新代码，继续往下执行..."
    else
        git commit -m "$commit_msg"
    fi
    git push || { echo "❌ Git 推送失败！"; exit 1; }

    echo ""
    echo "⚙️ 步骤 2/5: 清理旧的构建环境..."
    rm -rf build dist *.spec
    echo "✅ 清理完成。"

    echo ""
    echo "⚙️ 步骤 3/5: 开始本地构建 Mac 版本 (智能探测 + 极限瘦身)..."
    
    PYINSTALLER_BASE_ARGS=(
        "--noconfirm"
        "--clean"
        "--onedir"
        "--add-binary" "ffmpeg:."
        "--add-binary" "ffprobe:."
        "--hidden-import" "faster_whisper"
        "--hidden-import" "whisper"
        "--hidden-import" "stable_whisper"
        "--collect-all" "torch"
        "--exclude-module" "torch.test"
        "--exclude-module" "torch.distributions"
        "--exclude-module" "torch.utils.tensorboard"
        "--exclude-module" "matplotlib"
        "--exclude-module" "tkinter"
    )

    DUAL_BUILD=false

    if [ -d "arm64_venv" ] && [ -d "intel_venv" ]; then
        DUAL_BUILD=true
        echo ">>> 检测到双架构虚拟环境，开始分别构建 Mac Arm64 和 Intel 版本..."
        
        echo "🍎 [1/2] 正在构建 Mac Arm64 版本..."
        download_ffmpeg "arm64"
        source arm64_venv/bin/activate
        arch -arm64 python3 -m PyInstaller "${PYINSTALLER_BASE_ARGS[@]}" --target-arch arm64 --name "LRCMaker_Backend_Mac_Arm64" api_server.py || { echo "❌ Mac Arm64 打包失败！"; exit 1; }
        deactivate

        echo "🦋 [2/2] 正在构建 Mac Intel (x86_64) 版本..."
        download_ffmpeg "amd64"
        source intel_venv/bin/activate
        arch -x86_64 python3 -m PyInstaller "${PYINSTALLER_BASE_ARGS[@]}" --target-arch x86_64 --name "LRCMaker_Backend_Mac_Intel" api_server.py || { echo "❌ Mac Intel 打包失败！"; exit 1; }
        deactivate
        
        # 打包结束后恢复本机默认的 arm64 版 ffmpeg 以便日常开发使用
        download_ffmpeg "arm64"
        
    elif [ -d "venv" ]; then
        echo ">>> ⚠️ 未检测到 arm64_venv/intel_venv，但发现了常规 venv。"
        echo ">>> 将自动降级，仅构建当前系统架构的单版本 Mac 包..."
        
        download_ffmpeg "arm64"
        source venv/bin/activate
        arch -arm64 python3 -m PyInstaller "${PYINSTALLER_BASE_ARGS[@]}" --target-arch arm64 --name "LRCMaker_Backend_Mac" api_server.py || { echo "❌ Mac 本地打包失败！"; exit 1; }
        deactivate
    else
        echo "❌ [致命错误] 未找到任何虚拟环境！请先运行 ./switch_env.sh"
        exit 1
    fi

    echo ""
    echo "⚙️ 步骤 4/5: 🧠 预下载并注入 AI 离线模型..."
    
    if [ "$DUAL_BUILD" = true ]; then
        source arm64_venv/bin/activate
        echo ">>> 正在拉取 faster-whisper-small 模型并注入 M 芯片版..."
        arch -arm64 python3 -c "from huggingface_hub import snapshot_download; snapshot_download(repo_id='Systran/faster-whisper-small', local_dir='dist/LRCMaker_Backend_Mac_Arm64/models/faster-whisper-small')"
        echo ">>> 正在同步复制模型至 Intel 芯片版 (免重复下载)..."
        mkdir -p "dist/LRCMaker_Backend_Mac_Intel/models"
        cp -R "dist/LRCMaker_Backend_Mac_Arm64/models/faster-whisper-small" "dist/LRCMaker_Backend_Mac_Intel/models/"
        deactivate
    else
        source venv/bin/activate
        echo ">>> 正在拉取模型并注入单架构版..."
        arch -arm64 python3 -c "from huggingface_hub import snapshot_download; snapshot_download(repo_id='Systran/faster-whisper-small', local_dir='dist/LRCMaker_Backend_Mac/models/faster-whisper-small')"
        deactivate
    fi

    echo ""
    echo "📦 正在压缩 Mac 发布包 (保留系统软链接)..."
    cd dist
    if [ "$DUAL_BUILD" = true ]; then
        zip -ry -q "$arm64_zip_name" LRCMaker_Backend_Mac_Arm64
        zip -ry -q "$intel_zip_name" LRCMaker_Backend_Mac_Intel
        echo "✅ Mac Arm64 版本已生成至: dist/$arm64_zip_name"
        echo "✅ Mac Intel 版本已生成至: dist/$intel_zip_name"
    else
        zip -ry -q "$mac_zip_name" LRCMaker_Backend_Mac
        echo "✅ Mac 单架构版本已生成至: dist/$mac_zip_name"
    fi
    cd ..

    echo ""
    echo "⚙️ 步骤 5/5: 触发 Windows 云端打包..."
    git tag -f "$full_version"
    git push origin -f "$full_version" || { echo "❌ 触发云端构建失败！"; exit 1; }
    
    echo ""
    echo "🎉 大功告成！全平台部署指令已执行完毕。"
    echo "👉 GitHub Actions 正在为你打包内置离线模型的 Windows 版本！"
else
    echo "❌ 无效的选项，请重新运行脚本。"
    exit 1
fi