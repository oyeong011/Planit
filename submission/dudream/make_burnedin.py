"""
자막 번인 영상 생성:
  1. 슬라이드별 음성 길이를 자막 글자 수에 비례 분배
  2. 자막을 슬라이드 PNG에 PIL로 합성 → 자막당 1장의 PNG
  3. ffmpeg concat demuxer 로 슬라이드별 클립 (페이드 적용)
  4. 14개 클립 합쳐 final_presentation.mp4 덮어쓰기
"""

import os, subprocess, shlex, shutil
from PIL import Image, ImageDraw, ImageFont
from narration import NARRATION

ROOT   = "/Users/oy/Projects/Planit/submission/dudream"
SLIDES = os.path.join(ROOT, "slides")
WORK   = os.path.join(ROOT, "_burn")
AUDIO  = os.path.join(WORK, "audio")
PNGS   = os.path.join(WORK, "pngs")
CLIPS  = os.path.join(WORK, "clips")
OUT    = os.path.join(ROOT, "final_presentation.mp4")

for d in (WORK, AUDIO, PNGS, CLIPS):
    os.makedirs(d, exist_ok=True)

FONT_BOLD = os.path.expanduser("~/Library/Fonts/Pretendard-Bold.ttf")
FONT_MED  = os.path.expanduser("~/Library/Fonts/Pretendard-Medium.ttf")

VOICE = "Yuna"
RATE  = 180
LEAD  = 0.4
TRAIL = 0.6
FADE  = 0.4


def run(cmd):
    if isinstance(cmd, str): cmd = shlex.split(cmd)
    subprocess.run(cmd, check=True)

def dur(path):
    return float(subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", path],
        capture_output=True, text=True, check=True).stdout.strip())


# ---------- 1. TTS ---------- #
print("STEP 1: TTS")
audios, audio_durs = [], []
for i, text in enumerate(NARRATION, 1):
    aiff = os.path.join(AUDIO, f"slide-{i:02d}.aiff")
    wav  = os.path.join(AUDIO, f"slide-{i:02d}.wav")
    t = " ".join(text.split())
    if not os.path.exists(wav):
        run(["say", "-v", VOICE, "-r", str(RATE), "-o", aiff, t])
        run(["ffmpeg", "-y", "-loglevel", "error",
             "-i", aiff, "-ac", "1", "-ar", "44100", wav])
    audios.append(wav)
    audio_durs.append(dur(wav))
    print(f"  {i:02d}: {audio_durs[-1]:.1f}s")


# ---------- 2. 자막 분할 ---------- #
def split_sentences(text):
    text = " ".join(text.split())
    parts, cur = [], ""
    for ch in text:
        cur += ch
        if ch in ".!?":
            parts.append(cur.strip()); cur = ""
    if cur.strip(): parts.append(cur.strip())
    out = []
    for p in parts:
        if len(p) > 38 and "," in p:
            # 콤마 단위로 분할 (각 조각도 너무 길면 추가 분할)
            chunks = [c.strip() for c in p.split(",") if c.strip()]
            out.extend(chunks)
        else:
            out.append(p)
    # 마침표/콤마를 표시용으로 정리
    return [s.rstrip(",.") for s in out if s]


# 슬라이드별 자막 + 슬라이드 내 (start_in_slide, duration) 계산
all_subs = []   # [(slide_idx, sub_idx, text, dur_in_slide)]
for i, text in enumerate(NARRATION):
    subs = split_sentences(text)
    total_chars = sum(len(s) for s in subs) or 1
    seg_dur = audio_durs[i]
    for k, s in enumerate(subs):
        share = len(s) / total_chars
        d = max(0.9, seg_dur * share)
        all_subs.append((i, k, s, d))
# 길이 정규화: 각 슬라이드 자막 합 == audio_dur 가 되도록 보정
from collections import defaultdict
per_slide = defaultdict(list)
for idx, (i, k, s, d) in enumerate(all_subs):
    per_slide[i].append((idx, s, d))
adjusted = {}
for i, items in per_slide.items():
    total = sum(d for _, _, d in items)
    if total <= 0: continue
    scale = audio_durs[i] / total
    for idx, s, d in items:
        adjusted[idx] = d * scale
all_subs = [(i, k, s, adjusted.get(j, d)) for j, (i, k, s, d) in enumerate(all_subs)]

print(f"\n자막: {len(all_subs)}개")


# ---------- 3. 슬라이드+자막 PNG 합성 ---------- #
print("\nSTEP 3: 자막 번인 PNG 생성")

def wrap_lines(draw, text, font, max_w):
    """글자 단위(영문은 단어 단위)로 줄바꿈"""
    if not text: return [""]
    words = text.split(" ")
    lines, cur = [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        bbox = draw.textbbox((0, 0), trial, font=font)
        if bbox[2] - bbox[0] <= max_w:
            cur = trial
        else:
            if cur: lines.append(cur)
            cur = w
            # 한 단어가 너무 길면 글자 단위로 강제 분할
            while True:
                bb = draw.textbbox((0, 0), cur, font=font)
                if bb[2] - bb[0] <= max_w: break
                # 가장 긴 단어 분할
                for split_at in range(len(cur) - 1, 0, -1):
                    if draw.textbbox((0, 0), cur[:split_at], font=font)[2] <= max_w:
                        lines.append(cur[:split_at])
                        cur = cur[split_at:]
                        break
                else:
                    break
    if cur: lines.append(cur)
    return lines

def render_with_sub(slide_path, sub_text, out_path):
    base = Image.open(slide_path).convert("RGB")
    W, H = base.size
    # 슬라이드 하단 영역에 반투명 박스 + 자막
    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)

    if not sub_text.strip():
        base.save(out_path, "PNG", optimize=True)
        return

    # 폰트 크기 — 슬라이드 폭의 약 2.4%
    font_size = max(36, int(W * 0.026))
    font = ImageFont.truetype(FONT_BOLD, font_size)

    max_text_w = int(W * 0.82)
    lines = wrap_lines(od, sub_text, font, max_text_w)
    line_h = font.size + int(font.size * 0.25)
    pad_x = int(font.size * 0.9)
    pad_y = int(font.size * 0.55)

    # 박스 크기 계산
    max_line_w = 0
    for ln in lines:
        bb = od.textbbox((0, 0), ln, font=font)
        max_line_w = max(max_line_w, bb[2] - bb[0])
    box_w = max_line_w + 2 * pad_x
    box_h = len(lines) * line_h + 2 * pad_y - int(font.size * 0.25)

    # 박스 위치: 하단에서 70px 위
    bottom_margin = int(H * 0.07)
    box_x1 = (W - box_w) // 2
    box_y1 = H - bottom_margin - box_h
    box_x2 = box_x1 + box_w
    box_y2 = box_y1 + box_h

    # 둥근 박스 (검정 80% 투명)
    od.rounded_rectangle((box_x1, box_y1, box_x2, box_y2),
                          radius=18, fill=(15, 23, 32, 210))
    # 텍스트 (흰색)
    y = box_y1 + pad_y
    for ln in lines:
        bb = od.textbbox((0, 0), ln, font=font)
        lw = bb[2] - bb[0]
        x = box_x1 + (box_w - lw) // 2
        od.text((x, y), ln, font=font, fill=(255, 255, 255, 255))
        y += line_h

    out = Image.alpha_composite(base.convert("RGBA"), overlay).convert("RGB")
    out.save(out_path, "PNG", optimize=True)


# 슬라이드별로 PNG들 + concat 파일 생성
print()
for slide_idx in range(len(NARRATION)):
    items = [(i, s, d) for j, (i, k, s, d) in enumerate(all_subs) if i == slide_idx]
    items = sorted([(k, s, d) for j, (i, k, s, d) in enumerate(all_subs) if i == slide_idx],
                    key=lambda x: x[0])
    slide_png = os.path.join(SLIDES, f"slide-{slide_idx+1:02d}.png")
    concat_lines = []
    # 슬라이드 시작 LEAD 무음 — 자막 없음
    plain_png = os.path.join(PNGS, f"plain-{slide_idx+1:02d}.png")
    if not os.path.exists(plain_png):
        render_with_sub(slide_png, "", plain_png)
    concat_lines.append(f"file '{plain_png}'\nduration {LEAD:.3f}\n")
    for k, s, d in items:
        png = os.path.join(PNGS, f"sub-{slide_idx+1:02d}-{k:03d}.png")
        if not os.path.exists(png):
            render_with_sub(slide_png, s, png)
        concat_lines.append(f"file '{png}'\nduration {d:.3f}\n")
    # 슬라이드 끝 TRAIL 무음
    concat_lines.append(f"file '{plain_png}'\nduration {TRAIL:.3f}\n")
    concat_lines.append(f"file '{plain_png}'\n")  # concat demuxer 요구사항: 마지막 file 한번 더
    list_path = os.path.join(WORK, f"slide-{slide_idx+1:02d}.txt")
    with open(list_path, "w") as f:
        f.write("".join(concat_lines))
    print(f"  slide {slide_idx+1:02d}: {len(items)} 자막")


# ---------- 4. 슬라이드별 클립 빌드 (페이드 포함) ---------- #
print("\nSTEP 4: 클립 빌드")
clip_paths = []
for i in range(len(NARRATION)):
    list_path = os.path.join(WORK, f"slide-{i+1:02d}.txt")
    audio = audios[i]
    out = os.path.join(CLIPS, f"clip-{i+1:02d}.mp4")
    total = LEAD + audio_durs[i] + TRAIL

    vfilt = (
        "scale=1920:1080:force_original_aspect_ratio=decrease,"
        "pad=1920:1080:(ow-iw)/2:(oh-ih)/2:white,"
        f"fade=t=in:st=0:d={FADE},"
        f"fade=t=out:st={total-FADE:.3f}:d={FADE},"
        "format=yuv420p"
    )
    afilt = (
        f"[1:a]adelay={int(LEAD*1000)}|{int(LEAD*1000)},"
        f"apad=pad_dur={TRAIL},"
        f"afade=t=in:st=0:d=0.25,"
        f"afade=t=out:st={total-0.3:.3f}:d=0.3[a]"
    )
    run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "concat", "-safe", "0", "-i", list_path,
        "-i", audio,
        "-filter_complex", f"[0:v]{vfilt}[v];{afilt}",
        "-map", "[v]", "-map", "[a]",
        "-c:v", "libx264", "-tune", "stillimage",
        "-preset", "medium", "-crf", "20",
        "-c:a", "aac", "-b:a", "192k", "-ar", "44100",
        "-r", "30", "-t", f"{total:.3f}",
        out
    ])
    clip_paths.append(out)
    print(f"  clip {i+1:02d}: {total:.1f}s")


# ---------- 5. concat 최종 ---------- #
print("\nSTEP 5: 최종 concat")
list_file = os.path.join(WORK, "final.txt")
with open(list_file, "w") as f:
    for p in clip_paths:
        f.write(f"file '{p}'\n")
run([
    "ffmpeg", "-y", "-loglevel", "error",
    "-f", "concat", "-safe", "0", "-i", list_file,
    "-c", "copy", OUT
])

total = sum(LEAD + d + TRAIL for d in audio_durs)
m, s = divmod(int(total), 60)
print(f"\n✓ 자막 번인 영상 완성: {OUT}")
print(f"  길이: {m}분 {s}초")
print(f"  크기: {os.path.getsize(OUT)/1024/1024:.1f} MB")
