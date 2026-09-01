"""
ElevenLabs 한국어 네이티브 음성 생성 (Minjoon)
14장 슬라이드 내레이션 → MP3 → WAV (44100Hz mono)
출력: _burn/audio/slide-NN.wav (make_burnedin.py가 이 wav를 사용)
"""

import os, subprocess, sys, json
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from narration import NARRATION

ROOT = "/Users/oy/Projects/Planit/submission/dudream"
WORK = os.path.join(ROOT, "_burn")
AUDIO = os.path.join(WORK, "audio")

VOICE_ID = "8cOkLISXzLWeGEsu0cZC"   # Minjoon - Korean Male Narrator
MODEL    = "eleven_multilingual_v2"

with open(os.path.expanduser("~/.elevenlabs_key")) as f:
    API_KEY = f.read().strip()

VOICE_SETTINGS = {
    "stability": 0.55,        # 차분함 유지
    "similarity_boost": 0.75, # 원본 보이스 충실도
    "style": 0.15,            # 약간의 감정 표현
    "use_speaker_boost": True,
}

os.makedirs(AUDIO, exist_ok=True)

def tts(text, out_mp3):
    """ElevenLabs API → MP3 (urllib 사용, 외부 의존성 없음)"""
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}"
    payload = json.dumps({
        "text": " ".join(text.split()),
        "model_id": MODEL,
        "voice_settings": VOICE_SETTINGS,
    }).encode("utf-8")
    req = Request(url, data=payload, method="POST")
    req.add_header("xi-api-key", API_KEY)
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "audio/mpeg")
    try:
        with urlopen(req, timeout=120) as resp:
            data = resp.read()
    except HTTPError as e:
        print(f"  ✗ API 에러 ({e.code}): {e.read()[:200]}")
        sys.exit(1)
    with open(out_mp3, "wb") as f:
        f.write(data)


def mp3_to_wav(mp3, wav):
    subprocess.run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-i", mp3, "-ac", "1", "-ar", "44100", wav
    ], check=True)


def get_duration(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", path],
        capture_output=True, text=True, check=True).stdout.strip()
    return float(out)


print(f"=" * 60)
print(f"ElevenLabs Minjoon — 14장 음성 생성")
print(f"=" * 60)
total_chars = 0
for i, text in enumerate(NARRATION, 1):
    text_clean = " ".join(text.split())
    char_count = len(text_clean)
    total_chars += char_count
    mp3 = os.path.join(AUDIO, f"slide-{i:02d}.mp3")
    wav = os.path.join(AUDIO, f"slide-{i:02d}.wav")
    print(f"  슬라이드 {i:02d} ({char_count}자) → ", end="", flush=True)
    tts(text, mp3)
    mp3_to_wav(mp3, wav)
    d = get_duration(wav)
    print(f"{d:.1f}초")

print(f"\n✓ 14장 모두 생성 완료")
print(f"  총 글자 수: {total_chars:,}자")
print(f"  저장 위치: {AUDIO}/slide-NN.wav")
