"""
두드림 프로젝트 제출 배너 — 팀 왈라비 / 캘린
규격: 600 x 1200 mm  (1 : 2 비율)
출력: banner.png  (1400 x 2800 px, 인쇄용 확대 가능)
"""

from PIL import Image, ImageDraw, ImageFilter
from PIL import ImageFont
import os, textwrap

ROOT = "/Users/oy/Projects/Planit"
OUT  = os.path.join(ROOT, "submission/dudream/banner.png")

FONT_DIR  = os.path.expanduser("~/Library/Fonts")
FONT_BLACK = os.path.join(FONT_DIR, "Pretendard-Black.otf")
FONT_BOLD  = os.path.join(FONT_DIR, "Pretendard-Bold.ttf")
FONT_SEMI  = os.path.join(FONT_DIR, "Pretendard-SemiBold.otf")
FONT_MED   = os.path.join(FONT_DIR, "Pretendard-Medium.ttf")
FONT_REG   = os.path.join(FONT_DIR, "Pretendard-Regular.ttf")

# ---------- 캔버스 ---------- #
W, H = 2000, 4000     # 600x1200mm 비율 (1:2, 인쇄 100dpi 기준 약 508x1016mm)
MARGIN = 120

# ---------- 색 (왈라비 톤: 숭실 네이비 + 오렌지 액센트) ---------- #
BG_TOP      = (244, 248, 253)
BG_BOTTOM   = (255, 255, 255)
INK         = (15, 27, 45)
INK_SOFT    = (63, 76, 96)
INK_MUTE    = (120, 130, 149)
ACCENT      = (30, 77, 140)        # 숭실 네이비
ACCENT_DARK = (18, 51, 94)
ACCENT_SOFT = (216, 227, 242)
WALLABY     = (224, 109, 57)       # 왈라비 오렌지
SUCCESS     = (29, 158, 101)
WARN        = (217, 74, 74)
CARD        = (255, 255, 255)
LINE        = (219, 227, 236)
DUDR        = (220, 38, 38)

img = Image.new("RGB", (W, H), BG_BOTTOM)
draw = ImageDraw.Draw(img)

# ---------- 그라데이션 헤더 ---------- #
GRAD_H = 520
for y in range(GRAD_H):
    t = y / GRAD_H
    r = int(BG_TOP[0] * (1 - t) + BG_BOTTOM[0] * t)
    g = int(BG_TOP[1] * (1 - t) + BG_BOTTOM[1] * t)
    b = int(BG_TOP[2] * (1 - t) + BG_BOTTOM[2] * t)
    draw.line([(0, y), (W, y)], fill=(r, g, b))


def f(path, size):
    return ImageFont.truetype(path, size)

def text_size(text, font):
    bbox = draw.textbbox((0, 0), text, font=font)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]

def wrap_text(text, font, max_w):
    words = text.split(" ")
    lines, cur = [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        tw, _ = text_size(trial, font)
        if tw <= max_w:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines

def draw_wrapped(x, y, text, font, max_w, fill, line_gap=14, align_center=False):
    lines = wrap_text(text, font, max_w)
    for line in lines:
        tw, th = text_size(line, font)
        if align_center:
            draw.text(((W - tw) // 2, y), line, font=font, fill=fill)
        else:
            draw.text((x, y), line, font=font, fill=fill)
        y += th + line_gap
    return y

def rounded(xy, radius=24, fill=CARD, border=None, shadow=False):
    x1, y1, x2, y2 = xy
    if shadow:
        sh = Image.new("RGBA", (x2 - x1 + 60, y2 - y1 + 60), (0, 0, 0, 0))
        shd = ImageDraw.Draw(sh)
        shd.rounded_rectangle((30, 30, sh.size[0] - 30, sh.size[1] - 30),
                              radius=radius, fill=(15, 27, 45, 30))
        sh = sh.filter(ImageFilter.GaussianBlur(18))
        img.paste(sh, (x1 - 30, y1 - 30), sh)
    draw.rounded_rectangle(xy, radius=radius, fill=fill,
                            outline=border, width=2 if border else 0)


# ============================================================
# 1. 헤더
# ============================================================
# 두드림 + 왈라비 배지
badge_text = "두드림 프로그램 · 팀 왈라비"
badge_font = f(FONT_BOLD, 32)
bw, bh = text_size(badge_text, badge_font)
bx = (W - bw) // 2 - 28
by = 90
draw.rounded_rectangle((bx, by, bx + bw + 56, by + 62),
                        radius=31, fill=WALLABY)
draw.text(((W - bw) // 2, by + 13), badge_text, font=badge_font, fill="white")

# 프로젝트 명 (대제목)
title_font = f(FONT_BLACK, 150)
title = "캘린"
tw, _ = text_size(title, title_font)
draw.text(((W - tw) // 2, 200), title, font=title_font, fill=INK)

# 영문 부제
en_font = f(FONT_BOLD, 60)
en = "Calen"
ew, _ = text_size(en, en_font)
draw.text(((W - ew) // 2, 380), en, font=en_font, fill=ACCENT)

# 한국어 부제
sub_font = f(FONT_SEMI, 38)
sub = "AI 기반 일정 자동 재구성 서비스"
sw, _ = text_size(sub, sub_font)
draw.text(((W - sw) // 2, 460), sub, font=sub_font, fill=ACCENT_DARK)

# 부제 보조
meta_font = f(FONT_MED, 26)
meta = "두드림 프로그램 최종 결과 발표  ·  2026.06.05"
mw, _ = text_size(meta, meta_font)
draw.text(((W - mw) // 2, 520), meta, font=meta_font, fill=INK_MUTE)

# 구분선
draw.line([(MARGIN + 100, 590), (W - MARGIN - 100, 590)], fill=LINE, width=2)


def section_label(y, num, label):
    """섹션 헤더 (번호 박스 + 라벨)"""
    draw.rounded_rectangle((MARGIN, y, MARGIN + 70, y + 70),
                            radius=14, fill=ACCENT)
    nf = f(FONT_BLACK, 36)
    nw, nh = text_size(num, nf)
    draw.text((MARGIN + (70 - nw) // 2, y + (70 - nh) // 2 - 6),
              num, font=nf, fill="white")
    lf = f(FONT_BLACK, 48)
    draw.text((MARGIN + 92, y + 6), label, font=lf, fill=INK)
    return y + 100


# ============================================================
# 2. 개요 (프로젝트 정의)
# ============================================================
y = 640
y = section_label(y, "01", "개요")

overview = (
    "캘린은 기존 일정 관리 도구가 단순 기록 기능에 머무르는 구조적 한계를 해결하기 위해, "
    "일정 간의 맥락을 계산 가능한 형태로 모델링하고 자동으로 재구성하는 "
    "AI 기반 일정 운영 모델을 설계·실험한 프로젝트입니다. "
    "본 프로젝트는 상용 서비스 개발이 아니라, AI · 알고리즘 · 시스템 설계 · UX 이론을 "
    "실제 문제 해결 과정에 통합 적용한 학문적 연구입니다."
)
body_font = f(FONT_REG, 28)
y = draw_wrapped(MARGIN, y, overview, body_font,
                  W - 2 * MARGIN, INK_SOFT, line_gap=15)

# 4개 학습 영역 칩
y += 10
chips = [
    ("AI 모델",   ACCENT_SOFT, ACCENT_DARK),
    ("알고리즘",  ACCENT_SOFT, ACCENT_DARK),
    ("시스템",    ACCENT_SOFT, ACCENT_DARK),
    ("UX",        ACCENT_SOFT, ACCENT_DARK),
]
chip_font = f(FONT_SEMI, 26)
cx = MARGIN
chip_h = 50
for t, bg, fg in chips:
    tw, _ = text_size(t, chip_font)
    cw = tw + 40
    draw.rounded_rectangle((cx, y, cx + cw, y + chip_h), radius=25, fill=bg)
    draw.text((cx + 20, y + 8), t, font=chip_font, fill=fg)
    cx += cw + 14
y += chip_h + 35


# ============================================================
# 3. 팀 구성
# ============================================================
y = section_label(y, "02", "팀 구성")

team_intro = "팀 왈라비 · 7명 · 4개 학부 협업"
ti_font = f(FONT_BOLD, 30)
draw.text((MARGIN, y), team_intro, font=ti_font, fill=ACCENT_DARK)
y += 50

members = [
    ("권오영", "팀장", "IT대학 컴퓨터학부 4학년",
     "전체 아키텍처 · Mac/iOS · UX"),
    ("김혜진", "팀원", "인문대학 문예창작학부 4학년",
     "PRD · KPI · HEART · 마케팅"),
    ("최수빈", "팀원", "IT대학 컴퓨터학부 4학년",
     "Calendar API · OAuth · 동기화"),
    ("송채은", "팀원", "IT대학 글로벌미디어학부 4학년",
     "UI 키트 · SEO · 광고 전략"),
    ("이수민", "팀원", "IT대학 글로벌미디어학부 3학년",
     "와이어프레임 · Figma · UT"),
    ("황영인", "팀원", "IT대학 글로벌미디어학부 4학년",
     "User Flow · UX 평가 · MAU"),
    ("이서현", "팀원", "AI대학 AI 융합학부 4학년",
     "알고리즘 V1/V2 · Cost Function"),
]
# 2열 배치 (4 + 3) — 압축형
card_w = (W - 2 * MARGIN - 20) // 2
card_h = 130
for i, (name, role, dept, work) in enumerate(members):
    col = i % 2
    row = i // 2
    cx = MARGIN + col * (card_w + 20)
    cy = y + row * (card_h + 14)
    rounded((cx, cy, cx + card_w, cy + card_h),
             radius=12, fill=CARD, border=LINE)
    # 역할 배지
    role_color = WALLABY if role == "팀장" else ACCENT
    role_font = f(FONT_BOLD, 18)
    rw, rh = text_size(role, role_font)
    draw.rounded_rectangle((cx + 16, cy + 14, cx + 16 + rw + 22, cy + 14 + 32),
                            radius=16, fill=role_color)
    draw.text((cx + 27, cy + 18), role, font=role_font, fill="white")
    # 이름
    name_font = f(FONT_BLACK, 28)
    draw.text((cx + 16 + rw + 36, cy + 14), name, font=name_font, fill=INK)
    # 소속
    dept_font = f(FONT_MED, 18)
    draw.text((cx + 16, cy + 58), dept, font=dept_font, fill=INK_MUTE)
    # 역할 설명
    work_font = f(FONT_MED, 20)
    draw.text((cx + 16, cy + 88), work, font=work_font, fill=INK_SOFT)
y += 4 * (card_h + 14) + 5

# 지도교수
prof_font = f(FONT_MED, 24)
prof = "지도교수  ·  신용태 (IT대학 컴퓨터학부)  ·  숭실대학교"
pw, _ = text_size(prof, prof_font)
draw.text(((W - pw) // 2, y), prof, font=prof_font, fill=INK_MUTE)
y += 60


# ============================================================
# 4. 핵심 학문 성과 — 이미지 2장 (KPI + V1 vs V2)
# ============================================================
y = section_label(y, "03", "핵심 학문 성과")

# 4 KPI 카드 (2x2)
kpis = [
    ("일정 재구성 성공률",   "55%",  "88%",   "▲ 33%p",  SUCCESS),
    ("스케줄링 의사결정",    "48초", "6.2초", "▼ 41.8초", SUCCESS),
    ("정신적 인지부하",      "7.6점", "3.8점", "▼ 50%",   SUCCESS),
    ("XAI 설명 가능성",      "2.1점", "4.7점", "▲ 2.6점", SUCCESS),
]
kpi_w = (W - 2 * MARGIN - 20) // 2
kpi_h = 180
for i, (label, before, after, delta, color) in enumerate(kpis):
    col = i % 2; row = i // 2
    cx = MARGIN + col * (kpi_w + 20)
    cy = y + row * (kpi_h + 20)
    rounded((cx, cy, cx + kpi_w, cy + kpi_h),
             radius=16, fill=CARD, border=LINE, shadow=True)
    # 라벨
    lbl_font = f(FONT_BOLD, 22)
    draw.text((cx + 24, cy + 18), label, font=lbl_font, fill=INK)
    # before
    bf_font = f(FONT_BOLD, 42)
    bw_, bh_ = text_size(before, bf_font)
    draw.text((cx + 34, cy + 64), before, font=bf_font, fill=INK_MUTE)
    bs_font = f(FONT_MED, 16)
    draw.text((cx + 34, cy + 116), "기존", font=bs_font, fill=INK_MUTE)
    # 화살표
    ar_font = f(FONT_BLACK, 34)
    arw, _ = text_size("→", ar_font)
    draw.text((cx + 34 + bw_ + 16, cy + 72), "→", font=ar_font, fill=ACCENT)
    # after
    af_font = f(FONT_BLACK, 48)
    af_x = cx + 34 + bw_ + 24 + arw + 16
    draw.text((af_x, cy + 62), after, font=af_font, fill=ACCENT)
    cs_font = f(FONT_BOLD, 16)
    draw.text((af_x, cy + 116), "Calen 적용 후",
              font=cs_font, fill=ACCENT)
    # 델타 배지
    dt_font = f(FONT_BOLD, 20)
    dtw, _ = text_size(delta, dt_font)
    draw.rounded_rectangle(
        (cx + (kpi_w - dtw - 36) // 2, cy + kpi_h - 42,
         cx + (kpi_w + dtw + 36) // 2, cy + kpi_h - 14),
        radius=14, fill=color)
    draw.text((cx + (kpi_w - dtw) // 2, cy + kpi_h - 38),
              delta, font=dt_font, fill="white")
y += 2 * (kpi_h + 20) + 30

# 캡션
cap_font = f(FONT_MED, 22)
cap = "[그림 1] 12주차 최종 도출 — 4개 핵심 KPI Before / After 비교"
draw.text((MARGIN, y), cap, font=cap_font, fill=INK_MUTE)
y += 50

# V1 vs V2 비교 (이미지 2 — 표 형태) — 동적 컬럼
v_card_h = 410
rounded((MARGIN, y, W - MARGIN, y + v_card_h),
         radius=16, fill=CARD, border=LINE, shadow=True)
vt_font = f(FONT_BOLD, 28)
draw.text((MARGIN + 30, y + 22),
          "알고리즘 V1 → V2 개선 (담당: 이서현)",
          font=vt_font, fill=INK)

# 컬럼: 항목 25% / V1 35% / V2 40%
table_x = MARGIN + 30
table_w = W - 2 * MARGIN - 60
col1_x = table_x
col2_x = table_x + int(table_w * 0.25)
col3_x = table_x + int(table_w * 0.60)
hdr_y = y + 85
hdr_font = f(FONT_BOLD, 22)
draw.text((col1_x, hdr_y), "비교 항목", font=hdr_font, fill=ACCENT)
draw.text((col2_x, hdr_y), "V1 (단방향 그리디)", font=hdr_font, fill=WARN)
draw.text((col3_x, hdr_y), "V2 (양방향 + Soft Penalty)",
          font=hdr_font, fill=SUCCESS)
draw.line([(table_x, hdr_y + 42), (table_x + table_w, hdr_y + 42)],
          fill=LINE, width=2)

rows = [
    ("탐색 방향",    "후방(Forward)만",      "양방향 (Forward + Backward)"),
    ("제약 처리",    "Hard Constraint",      "Soft Penalty 함수"),
    ("실패 시 대응", "에러 반환 / 중단",     "대안 제시 (Alternative)"),
    ("충돌 해결률",  "80% (8/10)",           "100% (10/10)"),
    ("평균 지연",    "35분",                  "18분 (▼ 17분 단축)"),
    ("우선순위 보존","85%",                   "92% (▲ +7%p)"),
]
row_font = f(FONT_MED, 21)
ry = hdr_y + 56
for k, v1, v2 in rows:
    draw.text((col1_x, ry), k, font=row_font, fill=INK)
    draw.text((col2_x, ry), v1, font=row_font, fill=INK_SOFT)
    draw.text((col3_x, ry), v2, font=row_font, fill=ACCENT_DARK)
    ry += 40

y += v_card_h + 20

# 캡션
cap2 = "[그림 2] V1(단방향 그리디) → V2(양방향 탐색 + Soft Penalty) 알고리즘 개선 비교"
draw.text((MARGIN, y), cap2, font=cap_font, fill=INK_MUTE)
y += 60


# ============================================================
# 5. 프로젝트 경과
# ============================================================
y = section_label(y, "04", "프로젝트 경과")

timeline = [
    ("1-3주차", "기획·설계 기반",
     "PRD · IA / User Flow · 와이어프레임 · API/OAuth 조사 · 알고리즘 변수 정의"),
    ("4-6주차", "프로토타입·연동",
     "핵심 화면 구현 · OAuth · 캘린더 PoC · 충돌 탐지 · 후보 생성"),
    ("7-9주차", "구현·검증·확장",
     "Mac 데모 안정화 · 10인 UT · 양방향 동기화 · iOS/iPad 착수"),
    ("10-12주차", "UX 검증·V2·최종",
     "UT 2차 · NASA-TLX · 알고리즘 V2 도입 · 최종 KPI 도출"),
]
t_label_font = f(FONT_BOLD, 22)
t_title_font = f(FONT_BOLD, 24)
t_body_font  = f(FONT_REG, 20)
row_h = 85
title_x = MARGIN + 240   # 동적 — 라벨 폭 + 여백
for i, (when, title, body) in enumerate(timeline):
    ry = y + i * row_h
    pad_x = 24
    lw, _ = text_size(when, t_label_font)
    draw.rounded_rectangle((MARGIN, ry, MARGIN + lw + pad_x * 2, ry + 42),
                            radius=10, fill=ACCENT_SOFT)
    draw.text((MARGIN + pad_x, ry + 7), when,
              font=t_label_font, fill=ACCENT_DARK)
    draw.text((title_x, ry + 0), title, font=t_title_font, fill=INK)
    draw.text((title_x, ry + 38), body, font=t_body_font, fill=INK_SOFT)

y += len(timeline) * row_h + 20


# ============================================================
# 6. 마무리 소감 (학문적 성과)
# ============================================================
y = section_label(y, "05", "마무리 소감")

# 인용 카드
q_font = f(FONT_MED, 22)
q_text = (
    "“이번 12주는 단순한 앱 개발이 아니라, AI 알고리즘 설계 · 시스템 아키텍처 · UX 이론 · "
    "사용자 평가 방법론을 통합 적용한 깊은 학습의 시간이었습니다. "
    "충돌 발생 시 부자연스러운 허들이 된 실시간 대화 추천 기능을 과감히 피벗하고, "
    "알고리즘 V1의 한계를 정직하게 인정하고 V2로 재설계한 과정에서 "
    "‘설계 가설을 데이터로 검증하고 다시 설계하는’ 연구의 자세를 직접 체득했습니다.”"
)
test_lines = wrap_text(q_text, q_font, W - 2 * MARGIN - 80)
_, line_h_ = text_size("가", q_font)
quote_h = 60 + len(test_lines) * (line_h_ + 16) + 30
rounded((MARGIN, y, W - MARGIN, y + quote_h),
         radius=18, fill=ACCENT_SOFT)
# 따옴표
draw.text((MARGIN + 30, y + 0), "“",
          font=f(FONT_BLACK, 120), fill=ACCENT)
draw_wrapped(MARGIN + 40, y + 50, q_text, q_font,
              W - 2 * MARGIN - 80, INK, line_gap=14)
y += quote_h + 30

# 학문적 기여 2개 카드
contribs = [
    ("XAI의 UX적 구현",
     "근거 메시지 + Before/After 대조 레이아웃이 신뢰도 향상의 핵심 요인임을 데이터로 입증",
     "2.1 → 4.7점"),
    ("Human-in-the-loop",
     "최종 확정 권한을 사용자에게 부여 — 자동화 거부감 완화, 서비스 수용성 극대화",
     "55% → 88%"),
]
ct_card_w = (W - 2 * MARGIN - 30) // 2
ct_card_h = 175
for i, (t, body, kpi) in enumerate(contribs):
    cx = MARGIN + i * (ct_card_w + 30)
    rounded((cx, y, cx + ct_card_w, y + ct_card_h),
             radius=16, fill=CARD, border=LINE)
    # 번호 띠
    draw.rounded_rectangle((cx, y, cx + 12, y + ct_card_h),
                            radius=6, fill=WALLABY if i == 1 else ACCENT)
    # 타이틀
    draw.text((cx + 28, y + 18), t,
              font=f(FONT_BOLD, 24), fill=INK)
    # 본문
    draw_wrapped(cx + 28, y + 60, body,
                  f(FONT_REG, 18), ct_card_w - 56, INK_SOFT, line_gap=8)
    # KPI 라벨
    kp_font = f(FONT_BOLD, 22)
    kw, _ = text_size(kpi, kp_font)
    draw.text((cx + ct_card_w - kw - 25, y + ct_card_h - 40),
              kpi, font=kp_font, fill=WALLABY if i == 1 else ACCENT)
y += ct_card_h + 35


# ============================================================
# 푸터
# ============================================================
draw.line([(MARGIN, y), (W - MARGIN, y)], fill=LINE, width=2)
y += 30
foot_font = f(FONT_SEMI, 26)
foot = "두드림 프로그램 최종 결과 발표  ·  2026.06.05"
fw, _ = text_size(foot, foot_font)
draw.text(((W - fw) // 2, y), foot, font=foot_font, fill=INK)
y += 55
team_font = f(FONT_MED, 22)
team = "팀 왈라비  ·  권오영(팀장) · 김혜진 · 최수빈 · 송채은 · 이수민 · 황영인 · 이서현"
tw_, _ = text_size(team, team_font)
draw.text(((W - tw_) // 2, y), team, font=team_font, fill=INK_MUTE)
y += 40
prof_font2 = f(FONT_MED, 22)
prof2 = "지도교수: 신용태 (IT대학 컴퓨터학부)   |   숭실대학교"
pw2, _ = text_size(prof2, prof_font2)
draw.text(((W - pw2) // 2, y), prof2, font=prof_font2, fill=INK_MUTE)


# ---------- 저장 ---------- #
img.save(OUT, "PNG", optimize=True)
print(f"banner saved: {OUT}  ({img.size[0]}x{img.size[1]} px)")
print(f"file size: {os.path.getsize(OUT) / 1024:.1f} KB")
print(f"실제 콘텐츠 종료 y: {y}")
