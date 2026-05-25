import os
import sys

os.environ["HF_ENDPOINT"] = "https://hf-mirror.com"

if getattr(sys, 'frozen', False):
    application_path = sys._MEIPASS if hasattr(sys, '_MEIPASS') else os.path.dirname(sys.executable)
    os.environ["PATH"] = application_path + os.pathsep + os.environ.get("PATH", "")

import tempfile
import stable_whisper
import multiprocessing
from contextlib import asynccontextmanager
from fastapi import FastAPI, File, UploadFile, Form
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

model = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global model
    print("🚀 正在初始化 AI 引擎 (首次启动可能需要下载模型)...")
    
    model_cache_dir = os.path.expanduser("~/.lrc_maker_models")
    os.makedirs(model_cache_dir, exist_ok=True)
    
    model = stable_whisper.load_faster_whisper(
        'small', 
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

def generate_lrc_content(audio_path: str, raw_lyrics_text: str, ti: str, ar: str, al: str) -> str:
    # 1. 预处理文本
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
        return "❌ 错误：未在文本中找到有效歌词，请检查排版。"

    # 2. 传给 AI 模型
    full_text = "\n".join(sung_lines)
    print("🧠 正在进行强制对齐推理...")
    result = model.align(audio_path, full_text, language='zh')

    all_words = []
    for seg in result.segments:
        for w in seg.words:
            all_words.append(w)

    lrc_lines = []
    
    # 3. 写入元信息
    if ti: lrc_lines.append(f"[ti:{ti}]")
    if ar: lrc_lines.append(f"[ar:{ar}]")
    if al: lrc_lines.append(f"[al:{al}]")
    
    # 4. 写入 Staff
    if staff_lines:
        first_word_start = all_words[0].start if all_words else 0.0
        safe_intro = max(0, first_word_start - 0.5)
        interval = safe_intro / max(1, len(staff_lines))
        for i, staff in enumerate(staff_lines):
            lrc_lines.append(f"{format_time(i * interval)}{staff}")

    # 5. 写入正片歌词与间奏
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
            lrc_lines.append(f"{format_time(prev_line_end_time + 0.2)} ")

        target_len = len(clean_str(line))
        current_len = 0
        current_line_end_time = start_time

        while word_idx < total_words and current_len < target_len:
            current_word = all_words[word_idx]
            current_len += len(clean_str(current_word.word))
            current_line_end_time = current_word.end
            word_idx += 1

        lrc_lines.append(f"{start_time_str}{line}")
        prev_line_end_time = current_line_end_time

    if prev_line_end_time > 0:
        lrc_lines.append(f"{format_time(prev_line_end_time + 1.0)} ")

    return "\n".join(lrc_lines)

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
        
        lrc_result = generate_lrc_content(tmp_path, lyrics, ti, ar, al)
        
        print("✅ 处理完成，返回数据给前端。")
        return {"code": 200, "message": "success", "data": lrc_result}
        
    except Exception as e:
        print(f"❌ 发生错误: {str(e)}")
        return {"code": 500, "message": str(e), "data": None}
        
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

if __name__ == "__main__":
    multiprocessing.freeze_support()
    
    uvicorn.run(app, host="127.0.0.1", port=8000)