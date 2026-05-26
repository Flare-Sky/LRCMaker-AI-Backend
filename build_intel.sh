#!/bin/bash
# 🤖 Flare 的专属 Intel Mac 全自动打包脚本

echo "🚀 进入 Intel 宇宙..."
# 1. 确保使用通用版 3.11 创建纯正 Intel 环境
/Library/Frameworks/Python.framework/Versions/3.11/bin/python3 -m venv intel_venv
source intel_venv/bin/activate

echo "📦 升级基建，强行防范 C++ 源码编译坑..."
# 2. 升级 pip 并绕过所有缓存，只拿二进制包！
python3 -m pip install --upgrade pip
pip install llvmlite numba --no-cache-dir --only-binary llvmlite,numba

echo "🔥 组装大部队..."
# 3. 安装剩下的全部依赖
pip install -r requirements.txt
pip install pyinstaller

echo "⚔️ 满血合体打包中..."
# 4. 连锅端 PyTorch，防止缺 .dylib 文件
python3 -m PyInstaller --name "LRCMaker_Backend_Intel" --onedir \
--add-binary "ffmpeg:." --add-binary "ffprobe:." \
--hidden-import faster_whisper \
--hidden-import whisper \
--hidden-import stable_whisper \
--collect-all torch \
api_server.py

echo "✅ 打包完成！可以去 dist 目录收割了！"