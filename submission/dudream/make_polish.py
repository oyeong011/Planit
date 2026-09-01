"""
영상 마감 폴리시:
  1. 슬라이드별 음성 길이로 SRT 자막 생성
  2. 슬라이드 클립에 페이드인/아웃 + 자막 번인
  3. concat → final_presentation.mp4 (덮어쓰기)
"""

import os, subprocess, shlex, textwrap
from narration import NARRATION

ROOT = "/Users/oy/Projects/Planit/submission/dudream"
SLIDES = os.path.join(ROOT, "slides")
AUDIO  = os.path.join(ROOT, "audio_polish")
VIDEO  = os.path.join(ROOT, "video_polish")
OUT    = os.path.join(ROOT, "final_presentation.mp4")
SRT    = os.path.join(ROOT, "final_presentation.srt")

os.makedirs(AUDIO, exist_ok=True)
os.makedirs(VIDEO, exist_ok=True)

VOICE = "Yuna"
RATE  = 180
LEAD  = 0.4
TRAIL = 0.6
FADE  = 0.35    # 페이드 길이


def run(cmd):
    if isinstance(cmd, str): cmd = shlex.split(cmd)
    subprocess.run(cmd, check=True)


def dur(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", path],
        capture_output=True, text=True, check=True).stdout.strip()
    return float(out)


# ---------- 1. TTS + 길이 측정 ---------- #
print("=" * 60)
print("STEP 1: TTS 생성 + 길이 측정")
print("=" * 60)
audio_paths, audio_durs = [], []
for i, text in enumerate(NARRATION, 1):
    aiff = os.path.join(AUDIO, f"slide-{i:02d}.aiff")
    wav  = os.path.join(AUDIO, f"slide-{i:02d}.wav")
    text_clean = " ".join(text.split())
    if not os.path.exists(wav):
        run(["say", "-v", VOICE, "-r", str(RATE), "-o", aiff, text_clean])
        run(["ffmpeg", "-y", "-loglevel", "error",
             "-i", aiff, "-ac", "1", "-ar", "44100", wav])
    audio_paths.append(wav)
    d = dur(wav)
    audio_durs.append(d)
    print(f"  slide {i:02d}: 음성 {d:5.1f}s")


# ---------- 2. SRT 자막 생성 ---------- #
print("=" * 60)
print("STEP 2: SRT 자막 생성")
print("=" * 60)

def fmt_ts(t):
    h = int(t // 3600); t -= h * 3600
    m = int(t // 60); t -= m * 60
    s = int(t); ms = int((t - s) * 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"

def split_sentences(text):
    """문장 단위 분할 (마침표/콤마/줄바꿈)."""
    text = " ".join(text.split())
    parts = []
    cur = ""
    for ch in text:
        cur += ch
        if ch in ".!?":
            parts.append(cur.strip())
            cur = ""
    if cur.strip():
        parts.append(cur.strip())
    # 너무 긴 문장은 다시 콤마 기준 분할
    out = []
    for p in parts:
        if len(p) > 40 and "," in p:
            chunks = [c.strip() for c in p.split(",") if c.strip()]
            # 마지막 항목에 마침표 다시 붙이기
            out.extend(chunks)
        else:
            out.append(p)
    return out

# 각 슬라이드 음성 시간을 문장 길이에 비례해 분배
srt_entries = []
cur_time = 0.0
for i, text in enumerate(NARRATION, 1):
    sentences = split_sentences(text)
    seg_dur = audio_durs[i - 1]
    # 클립 내 자막은 LEAD 이후부터 LEAD+seg_dur까지
    seg_start = cur_time + LEAD
    total_chars = sum(len(s) for s in sentences) or 1
    t = seg_start
    for s in sentences:
        share = len(s) / total_chars
        d = max(1.0, seg_dur * share)
        srt_entries.append((t, t + d, s))
        t += d
    # 이 클립 전체 길이 = LEAD + seg_dur + TRAIL
    cur_time += LEAD + seg_dur + TRAIL

with open(SRT, "w") as f:
    for idx, (start, end, text) in enumerate(srt_entries, 1):
        f.write(f"{idx}\n{fmt_ts(start)} --> {fmt_ts(end)}\n{text}\n\n")
print(f"  자막: {len(srt_entries)}개 / 저장: {SRT}")


# ---------- 3. 슬라이드 클립 (페이드 적용) ---------- #
print("=" * 60)
print("STEP 3: 클립 생성 (페이드인/아웃)")
print("=" * 60)
clip_paths = []
for i, audio in enumerate(audio_paths, 1):
    img = os.path.join(SLIDES, f"slide-{i:02d}.png")
    out = os.path.join(VIDEO, f"clip-{i:02d}.mp4")
    seg_dur = audio_durs[i - 1]
    total = LEAD + seg_dur + TRAIL

    # 비디오: scale + pad + fade in/out
    # 오디오: 앞 LEAD 무음 + audio + 뒤 TRAIL 무음
    vfilt = (
        f"scale=1920:1080:force_original_aspect_ratio=decrease,"
        f"pad=1920:1080:(ow-iw)/2:(oh-ih)/2:white,"
        f"fade=t=in:st=0:d={FADE},"
        f"fade=t=out:st={total-FADE:.3f}:d={FADE},"
        f"format=yuv420p"
    )
    afilt = (
        f"[1:a]adelay={int(LEAD*1000)}|{int(LEAD*1000)},"
        f"apad=pad_dur={TRAIL},"
        f"afade=t=in:st=0:d=0.2,"
        f"afade=t=out:st={total-0.3:.3f}:d=0.3[a]"
    )
    run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-loop", "1", "-framerate", "30", "-t", f"{total:.3f}", "-i", img,
        "-i", audio,
        "-filter_complex", f"[0:v]{vfilt}[v];{afilt}",
        "-map", "[v]", "-map", "[a]",
        "-c:v", "libx264", "-tune", "stillimage",
        "-preset", "medium", "-crf", "20",
        "-c:a", "aac", "-b:a", "192k", "-ar", "44100",
        "-r", "30", "-shortest", out
    ])
    clip_paths.append(out)
    print(f"  clip {i:02d}: {total:5.1f}s")


# ---------- 4. concat ---------- #
print("=" * 60)
print("STEP 4: 클립 합치기")
print("=" * 60)
list_file = os.path.join(VIDEO, "concat.txt")
with open(list_file, "w") as f:
    for p in clip_paths:
        f.write(f"file '{p}'\n")
run([
    "ffmpeg", "-y", "-loglevel", "error",
    "-f", "concat", "-safe", "0", "-i", list_file,
    "-c", "copy", OUT
])

total_dur = sum(LEAD + d + TRAIL for d in audio_durs)
m, s = divmod(int(total_dur), 60)
print(f"\n✓ 영상 갱신: {OUT}")
print(f"  길이: {m}분 {s}초")
print(f"  크기: {os.path.getsize(OUT)/1024/1024:.1f} MB")
print(f"  자막: {SRT}")
