#!/bin/bash
set -e 

echo "🚀 进入 Intel 宇宙..."
/Library/Frameworks/Python.framework/Versions/3.11/bin/python3 -m venv intel_venv
source intel_venv/bin/activate

echo "📥 自动获取静态版 FFmpeg 与 FFprobe..."
if [ ! -f "ffmpeg" ]; then
    echo "   - 本地未找到 ffmpeg，正在自动下载..."
    curl -L -o ffmpeg.zip https://evermeet.cx/ffmpeg/getrelease/zip
    unzip -q -o ffmpeg.zip
    rm ffmpeg.zip
fi

if [ ! -f "ffprobe" ]; then
    echo "   - 本地未找到 ffprobe，正在自动下载..."
    curl -L -o ffprobe.zip https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip
    unzip -q -o ffprobe.zip
    rm ffprobe.zip
fi
chmod +x ffmpeg ffprobe
echo "✅ 音视频重武器已就绪！"

echo "📦 升级基建与降级 Numpy..."
python3 -m pip install --upgrade pip
pip install llvmlite numba --no-cache-dir --only-binary llvmlite,numba
pip install -r requirements.txt
pip install "numpy<2" pyinstaller

echo "⚔️ 满血合体打包中..."
python3 -m PyInstaller --name "LRCMaker_Backend_Intel" --onedir \
--add-binary "ffmpeg:." --add-binary "ffprobe:." \
--hidden-import faster_whisper \
--hidden-import whisper \
--hidden-import stable_whisper \
--collect-all torch \
--exclude-module torch.test \
--exclude-module torch.distributions \
--exclude-module torch.utils.tensorboard \
--exclude-module matplotlib \
--exclude-module tkinter \
api_server.py

echo "✅ 打包彻底完成！可以去 dist 目录收割了！"