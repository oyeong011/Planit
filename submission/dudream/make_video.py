"""
슬라이드 PNG + Korean TTS → MP4 발표 영상
- macOS `say -v Yuna` 로 슬라이드별 음성 생성
- ffmpeg 로 슬라이드 + 오디오 결합, concat 으로 최종 영상
출력: final_presentation.mp4 (1080p, H.264, AAC)
"""

import os
import subprocess
import shlex
from narration import NARRATION

ROOT = "/Users/oy/Projects/Planit/submission/dudream"
SLIDES = os.path.join(ROOT, "slides")
AUDIO  = os.path.join(ROOT, "audio")
VIDEO  = os.path.join(ROOT, "video")
OUT    = os.path.join(ROOT, "final_presentation.mp4")

os.makedirs(AUDIO, exist_ok=True)
os.makedirs(VIDEO, exist_ok=True)

VOICE = "Yuna"
RATE  = 180         # 단어/분 (Korean default ~170, 약간 빠르게)
SLIDE_PAD = 0.6     # 음성 끝나고 추가 정지(초)
SLIDE_LEAD = 0.4    # 음성 시작 전 정지(초)


def run(cmd, **kwargs):
    if isinstance(cmd, str):
        cmd = shlex.split(cmd)
    print(">>", " ".join(cmd))
    subprocess.run(cmd, check=True, **kwargs)


def get_audio_duration(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", path],
        capture_output=True, text=True, check=True).stdout.strip()
    return float(out)


# ---------- 1. 슬라이드별 TTS ---------- #
print("=" * 60)
print("STEP 1: Korean TTS 생성")
print("=" * 60)
audio_paths = []
for i, text in enumerate(NARRATION, start=1):
    aiff = os.path.join(AUDIO, f"slide-{i:02d}.aiff")
    wav  = os.path.join(AUDIO, f"slide-{i:02d}.wav")
    # 마침표·줄바꿈을 적절히 정리
    text_clean = " ".join(text.split())
    run(["say", "-v", VOICE, "-r", str(RATE), "-o", aiff, text_clean])
    # aiff → wav (16k mono)
    run(["ffmpeg", "-y", "-loglevel", "error",
         "-i", aiff, "-ac", "1", "-ar", "44100", wav])
    audio_paths.append(wav)


# ---------- 2. 슬라이드 + 오디오 → 클립 ---------- #
print("=" * 60)
print("STEP 2: 슬라이드 + 오디오 클립 생성")
print("=" * 60)
clip_paths = []
durations = []
for i, audio in enumerate(audio_paths, start=1):
    img = os.path.join(SLIDES, f"slide-{i:02d}.png")
    out = os.path.join(VIDEO, f"clip-{i:02d}.mp4")
    dur_audio = get_audio_duration(audio)
    dur_total = SLIDE_LEAD + dur_audio + SLIDE_PAD
    durations.append(dur_total)

    # 패딩 오디오 (앞뒤 무음) + 이미지를 곱해 비디오 생성
    # 한 번에 처리: anullsrc 로 무음 생성 후 audio 와 concat
    filt = (
        f"[1:a]adelay={int(SLIDE_LEAD*1000)}|{int(SLIDE_LEAD*1000)},"
        f"apad=pad_dur={SLIDE_PAD}[a]"
    )
    run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-loop", "1", "-framerate", "30", "-t", f"{dur_total:.3f}", "-i", img,
        "-i", audio,
        "-filter_complex", filt,
        "-map", "0:v", "-map", "[a]",
        "-c:v", "libx264", "-pix_fmt", "yuv420p",
        "-r", "30", "-tune", "stillimage", "-preset", "medium", "-crf", "20",
        "-c:a", "aac", "-b:a", "192k", "-ar", "44100",
        "-shortest",
        "-vf", "scale=1920:1080:force_original_aspect_ratio=decrease,"
               "pad=1920:1080:(ow-iw)/2:(oh-ih)/2:white",
        out
    ])
    clip_paths.append(out)
    print(f"  slide {i:02d}: {dur_total:.1f}s  ({dur_audio:.1f}s 음성 + {SLIDE_LEAD+SLIDE_PAD:.1f}s 패딩)")


# ---------- 3. concat ---------- #
print("=" * 60)
print("STEP 3: 클립 합치기")
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

total = sum(durations)
mins, secs = divmod(int(total), 60)
print(f"\n✓ 영상 완성: {OUT}")
print(f"  길이: {mins}분 {secs}초  ({total:.1f}초)")
print(f"  슬라이드: {len(clip_paths)}장")
print(f"  파일 크기: {os.path.getsize(OUT) / 1024 / 1024:.1f} MB")
