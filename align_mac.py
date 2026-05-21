import os
import stable_whisper

def format_time(seconds):
    """将秒数转换为 LRC 标准时间格式 [mm:ss.xx]"""
    minutes = int(seconds // 60)
    remaining_seconds = seconds % 60
    return f"[{minutes:02d}:{remaining_seconds:05.2f}]"

def clean_str(s):
    """去除所有空白字符，用于精准计算文字长度"""
    return s.replace(" ", "").replace("\n", "").replace("\r", "").replace("\t", "")

def align_lyrics(audio_path, text_path, output_lrc_path, ti="", ar="", al=""):
    print("正在预处理歌词文本...")
    
    with open(text_path, 'r', encoding='utf-8') as f:
        raw_lines = f.readlines()
        
    # ==========================================
    # 分离 Staff 信息和正片有效歌词（支持 --- 分隔符）
    # ==========================================
    staff_lines = []
    sung_lines = []
    
    has_separator = any(line.strip() == "---" for line in raw_lines)
    is_sung_started = False
    
    for line in raw_lines:
        line = line.strip()
        if not line:
            continue
            
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
        print("❌ 错误：未在文件中找到有效歌词！")
        return
    # ==========================================
    
    # 拼接为单一字符串交给模型
    full_text = "\n".join(sung_lines)

    print("正在加载 Whisper 模型 (CPU)...")
    model = stable_whisper.load_faster_whisper('small', device="cpu")

    print("正在进行毫秒级强制对齐...")
    result = model.align(audio_path, full_text, language='zh')

    # 提取 AI 识别出的所有“字/词”单元
    all_words = []
    for seg in result.segments:
        for w in seg.words:
            all_words.append(w)

    print("对齐完毕！正在装配带元信息的最终 LRC...\n")
    
    lrc_lines = []
    
    # ==========================================
    # 写入 1：歌曲元信息 (ID3 Tags)
    # ==========================================
    if ti: lrc_lines.append(f"[ti:{ti}]")
    if ar: lrc_lines.append(f"[ar:{ar}]")
    if al: lrc_lines.append(f"[al:{al}]")
    if ti or ar or al:
        # 为了美观，如果有元信息，就打印出来看看
        print("\n".join(lrc_lines))
    
    # ==========================================
    # 写入 2：Staff 鸣谢（等差分配到前奏）
    # ==========================================
    if staff_lines:
        first_word_start = all_words[0].start if all_words else 0.0
        safe_intro = max(0, first_word_start - 0.5)
        interval = safe_intro / max(1, len(staff_lines))
        
        for i, staff in enumerate(staff_lines):
            staff_time = format_time(i * interval)
            lrc_line = f"{staff_time}{staff}"
            lrc_lines.append(lrc_line)
            print(lrc_line)

    # ==========================================
    # 写入 3：核心正片歌词
    # ==========================================
    word_idx = 0
    total_words = len(all_words)
    
    # 【新增功能】：初始化上一句结束时间和间奏阈值
    prev_line_end_time = -1.0
    interlude_threshold = 3.0  # 大于 3 秒判定为间奏

    for line in sung_lines:
        if word_idx < total_words:
            # 获取这一行第一个字的时间戳
            start_time = all_words[word_idx].start
            start_time_str = format_time(start_time)
        else:
            start_time = prev_line_end_time + 0.1
            start_time_str = "[99:99.99]" 

        # 【新增功能 1】：识别长间奏并插入空行
        # 如果距离上一句结束超过了阈值，且上一句存在有效时间
        if prev_line_end_time > 0 and (start_time - prev_line_end_time) > interlude_threshold:
            # 在上一句结束的 0.2 秒后插入空行
            interlude_line = f"{format_time(prev_line_end_time + 0.2)} "
            lrc_lines.append(interlude_line)
            print(interlude_line)

        target_len = len(clean_str(line))
        current_len = 0
        current_line_end_time = start_time

        while word_idx < total_words and current_len < target_len:
            current_word = all_words[word_idx]
            current_len += len(clean_str(current_word.word))
            current_line_end_time = current_word.end  # 记录当前吃到的最后一个字的结束时间
            word_idx += 1

        lrc_line = f"{start_time_str}{line}"
        lrc_lines.append(lrc_line)
        print(lrc_line) 
        
        # 【新增功能】：更新“上一句结束时间”供下一次循环计算间奏
        prev_line_end_time = current_line_end_time

    # 【新增功能 2】：结尾清屏
    # 全曲唱完后，在最后一句歌词结束的 1 秒后插入空行
    if prev_line_end_time > 0:
        outro_line = f"{format_time(prev_line_end_time + 1.0)} "
        lrc_lines.append(outro_line)
        print(outro_line)

    with open(output_lrc_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lrc_lines))
        
    print(f"\n✅ 成功！LRC已生成至: {output_lrc_path}")

def main():
    # 使用 os.path.expanduser 自动解析 Mac 的 Downloads 目录
    AUDIO = os.path.expanduser("~/Downloads/1.wav")
    TEXT = "lyrics.txt"      
    # 如果你也想把生成的 LRC 直接保存在 Downloads 目录，可以一并修改：
    # OUTPUT = os.path.expanduser("~/Downloads/mac_sync.lrc")
    OUTPUT = "mac_sync.lrc"
    
    if not (os.path.exists(AUDIO) and os.path.exists(TEXT)):
        print("❌ 错误：未找到测试音频或歌词文本，请检查文件名和路径！")
        return

    # ==========================================
    # 交互式收集元信息
    # ==========================================
    print("\n=== 🎵 LRC Maker (AI Core) ===")
    ti = input("请输入歌曲名称 [ti] (直接回车跳过): ").strip()
    ar = input("请输入演唱者 [ar] (直接回车跳过): ").strip()
    al = input("请输入专辑名称 [al] (直接回车跳过): ").strip()
    print("===============================\n")
    
    align_lyrics(AUDIO, TEXT, OUTPUT, ti, ar, al)

if __name__ == "__main__":
    main()