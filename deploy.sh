#!/bin/bash
set -e

echo "================================================="
echo " 🚀 LRCMaker AI 跨平台一键部署与同步脚本 (v2.0 终极版)"
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
    read -p "👉 请输入新版本号 (例如 1.0, 不需要输入v): " version
    full_version="v$version"
    mac_zip_name="LRCMaker-AI-Backend-Mac-$full_version.zip"

    echo ""
    echo "⚙️ 步骤 1/5: 提交并推送代码到 GitHub..."
    git add .
    read -p "请输入本次更新的 Commit 描述 (直接回车默认使用 'Release $full_version'): " commit_msg
    if [ -z "$commit_msg" ]; then
        commit_msg="Release $full_version"
    fi
    git commit -m "$commit_msg" || echo "⚠️ 没有检测到需要 commit 的新代码，继续往下执行..."
    git push || { echo "❌ Git 推送失败！请检查网络或处理分支冲突后重试。"; exit 1; }

    echo ""
    echo "⚙️ 步骤 2/5: 清理旧的构建环境..."
    rm -rf build dist *.spec
    echo "清理完成。"

    echo ""
    echo "⚙️ 步骤 3/5: 开始本地构建 Mac 版本..."
    python3 -m PyInstaller --name "LRCMaker_Backend" --onedir api_server.py || { 
        echo ""
        echo "❌ [致命错误] Mac 本地打包失败！"
        echo "👆 请向上翻阅终端里的红色报错日志（例如 SyntaxError），修复代码后重新运行脚本。"
        exit 1 
    }
    
    echo ""
    echo "⚙️ 步骤 4/5: 🧠 云端预下载 AI 模型 (v2.0 纯离线特性)..."
    echo "正在拉取 faster-whisper-small 模型，塞入发布包中..."
    python3 -m pip install huggingface_hub
    python3 -c "from huggingface_hub import snapshot_download; snapshot_download(repo_id='Systran/faster-whisper-small', local_dir='dist/LRCMaker_Backend/models/faster-whisper-small')" || {
        echo "❌ [致命错误] AI 模型下载失败！请检查网络状态。"
        exit 1
    }
    
    echo ""
    echo "打包与模型植入成功！正在压缩 Mac 版本包 (保留系统软链接)..."
    cd dist
    zip -ry "$mac_zip_name" LRCMaker_Backend || { 
        echo "❌ [致命错误] 压缩 Mac 版本包失败！找不到目标文件夹。"; exit 1; 
    }
    cd ..
    echo "✅ Mac 版本已成功生成至: dist/$mac_zip_name"

    echo ""
    echo "⚙️ 步骤 5/5: 触发 Windows 云端打包..."
    git tag "$full_version" || { echo "❌ 打标签失败！可能由于该版本号($full_version)已存在。请先删除旧标签或更换版本号。"; exit 1; }
    git push origin "$full_version" || { echo "❌ [致命错误] 触发云端构建失败 (Git 推送 Tag 失败)！"; exit 1; }
    
    echo ""
    echo "🎉 大功告成！指令已发送至云端。"
    echo "👉 GitHub Actions 正在为你打包 Windows 版本并创建 Artifacts。"
    echo "👉 稍后请前往 GitHub 仓库的 Actions 页面，下载并检查你的 Windows 产物！"
else
    echo "❌ 无效的选项，请重新运行脚本。"
    exit 1
fi