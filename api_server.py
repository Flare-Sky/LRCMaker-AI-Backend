import os
import sys
import socket
import tempfile
import multiprocessing
from contextlib import asynccontextmanager

from fastapi import FastAPI, File, UploadFile, Form
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import stable_whisper

os.environ["HF_ENDPOINT"] = "https://hf-mirror.com"

if getattr(sys, 'frozen', False):
    application_path = sys._MEIPASS if hasattr(sys, '_MEIPASS') else os.path.dirname(sys.executable)
    os.environ["PATH"] = application_path + os.pathsep + os.environ.get("PATH", "")
else:
    application_path = os.path.dirname(os.path.abspath(__file__))

model = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global model
    print("🚀 正在初始化 AI 引擎...")
    
    model_cache_dir = os.path.expanduser("~/.lrc_maker_models")
    os.makedirs(model_cache_dir, exist_ok=True)
    
    local_model_path = os.path.join(application_path, "models", "faster-whisper-small")
    
    if os.path.exists(local_model_path) and os.listdir(local_model_path):
        print(f"📦 发现本地离线模型目录，直接加载免下载：\n   -> {local_model_path}")
        model_target = local_model_path
    else:
        print("🌐 未发现本地离线模型，将尝试从网络或系统缓存加载 'small' 模型...")
        print(f"   (提示：你可以手动下载模型并放入 {local_model_path} 目录实现完全离线运行)")
        model_target = 'small'
    
    model = stable_whisper.load_faster_whisper(
        model_target, 
        device="cpu", 
        download_root=model_cache_dir
    )
    
    print("✅ AI 引擎就绪！请不要关闭此黑色窗口。")
    print("👉 现在去网页里点击 [一键 AI 强制对齐] 吧！")
    yield

app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  
    allow_credentials=True,
    allow_methods=["*"],  
    allow_headers=["*"],  
)

def format_time(seconds):
    minutes = int(seconds // 60)
    remaining_seconds = seconds % 60
    return f"[{minutes:02d}:{remaining_seconds:05.2f}]"

def clean_str(s):
    return s.replace(" ", "").replace("\n", "").replace("\r", "").replace("\t", "")

def generate_lrc_content(audio_path: str, raw_lyrics_text: str, ti: str, ar: str, al: str) -> dict:
    raw_lines = raw_lyrics_text.splitlines()
    staff_lines = []
    sung_lines = []
    has_separator = any(line.strip() == "---" for line in raw_lines)
    is_sung_started = False
    
    for line in raw_lines:
        line = line.strip()
        if not line: continue
        if has_separator:
            if line == "---":
                is_sung_started = True
                continue
            if not is_sung_started:
                staff_lines.append(line)
            else:
                sung_lines.append(line)
        else:
            if not is_sung_started and (":" in line or "：" in line):
                staff_lines.append(line)
            else:
                is_sung_started = True
                sung_lines.append(line)
                
    if not sung_lines:
        return {"error": "❌ 错误：未在文本中找到有效歌词，请检查排版。"}

    full_text = "\n".join(sung_lines)
    print("🧠 正在进行强制对齐推理...")
    result = model.align(audio_path, full_text, language='zh')

    all_words = []
    for seg in result.segments:
        for w in seg.words:
            all_words.append(w)

    lrc_lines = []
    enhanced_lrc_lines = []
    
    meta_info = []
    if ti: meta_info.append(f"[ti:{ti}]")
    if ar: meta_info.append(f"[ar:{ar}]")
    if al: meta_info.append(f"[al:{al}]")
    lrc_lines.extend(meta_info)
    enhanced_lrc_lines.extend(meta_info)
    
    if staff_lines:
        first_word_start = all_words[0].start if all_words else 0.0
        safe_intro = max(0, first_word_start - 0.5)
        interval = safe_intro / max(1, len(staff_lines))
        for i, staff in enumerate(staff_lines):
            staff_str = f"{format_time(i * interval)}{staff}"
            lrc_lines.append(staff_str)
            enhanced_lrc_lines.append(staff_str)

    word_idx = 0
    total_words = len(all_words)
    prev_line_end_time = -1.0
    interlude_threshold = 3.0 

    for line in sung_lines:
        if word_idx < total_words:
            start_time = all_words[word_idx].start
            start_time_str = format_time(start_time)
        else:
            start_time = prev_line_end_time + 0.1
            start_time_str = "[99:99.99]" 

        if prev_line_end_time > 0 and (start_time - prev_line_end_time) > interlude_threshold:
            interlude_str = f"{format_time(prev_line_end_time + 0.2)} "
            lrc_lines.append(interlude_str)
            enhanced_lrc_lines.append(interlude_str)

        target_len = len(clean_str(line))
        current_len = 0
        current_line_end_time = start_time
        
        current_line_words = []

        while word_idx < total_words and current_len < target_len:
            current_word = all_words[word_idx]
            current_line_words.append(current_word)
            current_len += len(clean_str(current_word.word))
            current_line_end_time = current_word.end
            word_idx += 1

        lrc_lines.append(f"{start_time_str}{line}")
        
        enhanced_line_str = f"{start_time_str}"
        for w in current_line_words:
            clean_word = clean_str(w.word)
            if clean_word:
                enhanced_line_str += f"<{format_time(w.start)}>{clean_word}"
        enhanced_lrc_lines.append(enhanced_line_str)

        prev_line_end_time = current_line_end_time

    if prev_line_end_time > 0:
        end_str = f"{format_time(prev_line_end_time + 1.0)} "
        lrc_lines.append(end_str)
        enhanced_lrc_lines.append(end_str)

    return {
        "standard_lrc": "\n".join(lrc_lines),
        "enhanced_lrc": "\n".join(enhanced_lrc_lines)
    }

@app.post("/api/align")
async def api_align(
    audio: UploadFile = File(...),
    lyrics: str = Form(...),
    ti: str = Form(""),
    ar: str = Form(""),
    al: str = Form("")
):
    print(f"📥 收到请求：音频文件 [{audio.filename}], 文本长度 [{len(lyrics)}]")
    
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as tmp:
            tmp_path = tmp.name
            content = await audio.read()
            tmp.write(content)
            
        print("🎵 音频已保存至临时目录，开始处理...")
        
        lrc_result_dict = generate_lrc_content(tmp_path, lyrics, ti, ar, al)
        
        if isinstance(lrc_result_dict, dict) and "error" in lrc_result_dict:
            print(lrc_result_dict["error"])
            return {"code": 400, "message": lrc_result_dict["error"], "data": None}
            
        print("✅ 处理完成，返回标准与逐字双轨数据给前端。")
        return {"code": 200, "message": "success", "data": lrc_result_dict}
        
    except Exception as e:
        print(f"❌ 发生错误: {str(e)}")
        return {"code": 500, "message": str(e), "data": None}
        
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

def find_free_port(start_port=8000):
    """从指定的起始端口开始，寻找一个未被占用的本地端口"""
    port = start_port
    while port < 65535:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            if s.connect_ex(('127.0.0.1', port)) != 0:
                return port
        port += 1
    raise RuntimeError("无法找到可用的端口！")

if __name__ == "__main__":
    multiprocessing.freeze_support()

    active_port = find_free_port(8000)
    
    print("\n" + "="*50)
    print("🚀 LRCMaker 本地后端服务已点火！")
    print(f"🔌 当前 API 监听端口: {active_port}")
    if active_port != 8000:
        print(f"⚠️  注意：默认端口 8000 已被占用，已自动切换至 {active_port}")
        print(f"👉  【重要】请在你的浏览器插件/前端配置中，将后端地址改为: http://127.0.0.1:{active_port}")
    print("="*50 + "\n")
    
    uvicorn.run(app, host="127.0.0.1", port=active_port)