#!/bin/bash
set -e

echo "================================================="
echo " 🚀 LRCMaker AI 跨平台一键部署与同步脚本 (v2.0 智能探测版)"
echo "================================================="
echo "请选择你要执行的操作："
echo "1. 📥 从 GitHub 同步最新代码到本地 (Git Pull)"
echo "2. 📦 完整发布流程 (提交代码 -> 本地 Mac 打包 -> 云端 Win 打包)"
read -p "请输入选项 [1 或 2]: " choice

if [ "$choice" == "1" ]; then
    echo "👉 正在拉取云端代码..."
    git pull || { echo "❌ 同步失败！请检查是否有网络问题或代码冲突。"; exit 1; }
    echo "✅ 同步完成！"
    exit 0
elif [ "$choice" == "2" ]; then
    # 获取版本号
    read -p "👉 请输入新版本号 (例如 2.0, 不需要输入v): " version
    full_version="v$version"
    m1_zip_name="LRCMaker-AI-Backend-Mac-M1-$full_version.zip"
    intel_zip_name="LRCMaker-AI-Backend-Mac-Intel-$full_version.zip"
    mac_zip_name="LRCMaker-AI-Backend-Mac-$full_version.zip"

    echo ""
    echo "⚙️ 步骤 1/5: 提交并推送代码到 GitHub..."
    git add .
    read -p "请输入本次更新的 Commit 描述 (直接回车默认使用 'Release $full_version'): " commit_msg
    if [ -z "$commit_msg" ]; then
        commit_msg="Release $full_version"
    fi
    
    # 兼容 set -e 的安全 commit 方式
    if git diff --cached --quiet; then
        echo "⚠️ 没有检测到需要 commit 的新代码，继续往下执行..."
    else
        git commit -m "$commit_msg"
    fi
    git push || { echo "❌ Git 推送失败！请检查网络或处理分支冲突后重试。"; exit 1; }

    echo ""
    echo "⚙️ 步骤 2/5: 清理旧的构建环境..."
    rm -rf build dist *.spec
    echo "清理完成。"

    echo ""
    echo "⚙️ 步骤 3/5: 开始本地构建 Mac 版本 (智能探测环境)..."
    
    DUAL_BUILD=false

    if [ -d "m1_venv" ] && [ -d "intel_venv" ]; then
        DUAL_BUILD=true
        echo ">>> 检测到双架构虚拟环境，开始分别构建 Mac M1 和 Intel 版本..."
        
        source m1_venv/bin/activate
        python3 -m PyInstaller --name "LRCMaker_Backend_Mac_M1" --onedir api_server.py || { echo "❌ Mac M1 本地打包失败！"; exit 1; }
        deactivate

        source intel_venv/bin/activate
        python3 -m PyInstaller --name "LRCMaker_Backend_Mac_Intel" --onedir api_server.py || { echo "❌ Mac Intel 本地打包失败！"; exit 1; }
        deactivate
        
    elif [ -d "venv" ]; then
        echo ">>> ⚠️ 未检测到 m1_venv/intel_venv，但发现了常规 venv。"
        echo ">>> 将自动降级，仅构建当前系统架构的单版本 Mac 包..."
        
        source venv/bin/activate
        python3 -m PyInstaller --name "LRCMaker_Backend_Mac" --onedir api_server.py || { echo "❌ Mac 本地打包失败！"; exit 1; }
        deactivate
    else
        echo "❌ [致命错误] 未找到任何虚拟环境 (venv, m1_venv, intel_venv)！请先配置环境。"
        exit 1
    fi

    echo ""
    echo "⚙️ 步骤 4/5: 🧠 云端预下载 AI 模型 (v2.0 纯离线特性)..."
    echo "正在拉取 faster-whisper-small 模型，塞入发布包中..."
    
    if [ "$DUAL_BUILD" = true ]; then
        source m1_venv/bin/activate
        python3 -m pip install huggingface_hub
        echo ">>> 注入 M 芯片版..."
        python3 -c "from huggingface_hub import snapshot_download; snapshot_download(repo_id='Systran/faster-whisper-small', local_dir='dist/LRCMaker_Backend_Mac_M1/models/faster-whisper-small')" || { echo "❌ 模型下载失败"; exit 1; }
        echo ">>> 注入 Intel 芯片版..."
        python3 -c "from huggingface_hub import snapshot_download; snapshot_download(repo_id='Systran/faster-whisper-small', local_dir='dist/LRCMaker_Backend_Mac_Intel/models/faster-whisper-small')" || { echo "❌ 模型下载失败"; exit 1; }
        deactivate
    else
        source venv/bin/activate
        python3 -m pip install huggingface_hub
        echo ">>> 注入单架构版..."
        python3 -c "from huggingface_hub import snapshot_download; snapshot_download(repo_id='Systran/faster-whisper-small', local_dir='dist/LRCMaker_Backend_Mac/models/faster-whisper-small')" || { echo "❌ 模型下载失败"; exit 1; }
        deactivate
    fi
    
    echo ""
    echo "打包与模型植入成功！正在压缩 Mac 版本包 (保留系统软链接)..."
    cd dist
    if [ "$DUAL_BUILD" = true ]; then
        zip -ry "$m1_zip_name" LRCMaker_Backend_Mac_M1 || { echo "❌ 压缩 M1 版本包失败！"; exit 1; }
        zip -ry "$intel_zip_name" LRCMaker_Backend_Mac_Intel || { echo "❌ 压缩 Intel 版本包失败！"; exit 1; }
        echo "✅ Mac M 芯片版本已生成至: dist/$m1_zip_name"
        echo "✅ Mac Intel 版本已生成至: dist/$intel_zip_name"
    else
        zip -ry "$mac_zip_name" LRCMaker_Backend_Mac || { echo "❌ 压缩版本包失败！"; exit 1; }
        echo "✅ Mac 单架构版本已生成至: dist/$mac_zip_name"
    fi
    cd ..

    echo ""
    echo "⚙️ 步骤 5/5: 触发 Windows 云端打包..."
    git tag "$full_version" || { echo "❌ 打标签失败！可能由于该版本号($full_version)已存在。请先删除旧标签或更换版本号。"; exit 1; }
    git push origin "$full_version" || { echo "❌ [致命错误] 触发云端构建失败 (Git 推送 Tag 失败)！"; exit 1; }
    
    echo ""
    echo "🎉 大功告成！全平台部署指令已执行完毕。"
    echo "👉 你的桌面上（或 dist 目录中）现在有了离线版 Mac 压缩包。"
    echo "👉 GitHub Actions 也正在为你打包内置离线模型的 Windows 版本！"
else
    echo "❌ 无效的选项，请重新运行脚本。"
    exit 1
fi