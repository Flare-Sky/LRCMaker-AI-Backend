#!/bin/bash

echo "================================================="
echo " 🚀 LRCMaker AI 跨平台一键部署与同步脚本"
echo "================================================="
echo "请选择你要执行的操作："
echo "1. 📥 从 GitHub 同步最新代码到本地 (Git Pull)"
echo "2. 📦 完整发布流程 (提交代码 -> 本地 Mac 打包 -> 云端 Win 打包)"
read -p "请输入选项 [1 或 2]: " choice

if [ "$choice" == "1" ]; then
    echo "👉 正在拉取云端代码..."
    git pull
    echo "✅ 同步完成！"
    exit 0
elif [ "$choice" == "2" ]; then
    # 获取版本号
    read -p "👉 请输入新版本号 (例如 1.2, 不需要输入v): " version
    full_version="v$version"
    mac_zip_name="LRCMaker-AI-Backend-Mac-$full_version.zip"

    echo ""
    echo "⚙️ 步骤 1/4: 提交并推送代码到 GitHub..."
    git add .
    read -p "请输入本次更新的 Commit 描述 (直接回车默认使用 'Release $full_version'): " commit_msg
    if [ -z "$commit_msg" ]; then
        commit_msg="Release $full_version"
    fi
    git commit -m "$commit_msg"
    git push

    echo ""
    echo "⚙️ 步骤 2/4: 清理旧的构建环境..."
    rm -rf build dist *.spec
    echo "清理完成。"

    echo ""
    echo "⚙️ 步骤 3/4: 开始本地构建 Mac 版本..."
    # 使用你验证成功的命令
    python3 -m PyInstaller --name "LRCMaker_Backend" --onedir api_server.py
    
    echo "正在压缩 Mac 版本包 (保留系统软链接)..."
    cd dist
    zip -ry "$mac_zip_name" LRCMaker_Backend
    cd ..
    echo "✅ Mac 版本已成功生成至: dist/$mac_zip_name"

    echo ""
    echo "⚙️ 步骤 4/4: 触发 Windows 云端打包..."
    # 利用 Git Tag 触发 GitHub Actions
    git tag "$full_version"
    git push origin "$full_version"
    
    echo ""
    echo "🎉 大功告成！指令已发送至云端。"
    echo "👉 GitHub Actions 正在为你打包 Windows 版本并创建 Release。"
    echo "👉 你现在可以去喝杯咖啡，稍后前往 GitHub Releases 页面查看结果！"
else
    echo "❌ 无效的选项，请重新运行脚本。"
    exit 1
fi