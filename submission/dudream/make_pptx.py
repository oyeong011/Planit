"""
두드림 최종 결과 발표 — 팀 왈라비 / 프로젝트 캘린
12 슬라이드 (16:9), Pretendard, 발표 영상용 디자인
"""
import os
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.oxml.ns import qn
from lxml import etree

ROOT = "/Users/oy/Projects/Planit"
OUT  = os.path.join(ROOT, "submission/dudream/final_presentation.pptx")

# ---------- 색상 (왈라비 톤 — 차분한 청록/네이비) ---------- #
INK         = RGBColor(0x0F, 0x1B, 0x2D)
INK_SOFT    = RGBColor(0x3F, 0x4C, 0x60)
INK_MUTE    = RGBColor(0x78, 0x82, 0x95)
ACCENT      = RGBColor(0x1E, 0x4D, 0x8C)   # 숭실 네이비
ACCENT_DARK = RGBColor(0x12, 0x33, 0x5E)
ACCENT_SOFT = RGBColor(0xD8, 0xE3, 0xF2)
WALLABY     = RGBColor(0xE0, 0x6D, 0x39)   # 왈라비 오렌지
SUCCESS     = RGBColor(0x1D, 0x9E, 0x65)
WARN        = RGBColor(0xD9, 0x4A, 0x4A)
BG_SOFT     = RGBColor(0xF6, 0xF9, 0xFC)
WHITE       = RGBColor(0xFF, 0xFF, 0xFF)
LINE        = RGBColor(0xDB, 0xE3, 0xEC)

FONT = "Pretendard"

prs = Presentation()
prs.slide_width  = Inches(13.333)
prs.slide_height = Inches(7.5)
SW, SH = prs.slide_width, prs.slide_height
BLANK = prs.slide_layouts[6]


# ---------- 헬퍼 ---------- #
def add_rect(slide, x, y, w, h, fill, line=None):
    shp = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, x, y, w, h)
    shp.fill.solid(); shp.fill.fore_color.rgb = fill
    if line is None: shp.line.fill.background()
    else:
        shp.line.color.rgb = line; shp.line.width = Pt(0.75)
    shp.shadow.inherit = False
    return shp

def add_round(slide, x, y, w, h, fill, line=None, radius=0.08):
    shp = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, x, y, w, h)
    shp.adjustments[0] = radius
    shp.fill.solid(); shp.fill.fore_color.rgb = fill
    if line is None: shp.line.fill.background()
    else:
        shp.line.color.rgb = line; shp.line.width = Pt(0.75)
    shp.shadow.inherit = False
    return shp

def add_text(slide, x, y, w, h, text, *,
             size=18, bold=False, color=INK,
             align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP, line_spacing=1.2):
    box = slide.shapes.add_textbox(x, y, w, h)
    tf = box.text_frame
    tf.word_wrap = True
    tf.margin_left = Inches(0.04); tf.margin_right = Inches(0.04)
    tf.margin_top = Inches(0.02); tf.margin_bottom = Inches(0.02)
    tf.vertical_anchor = anchor
    lines = text.split("\n") if isinstance(text, str) else text
    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        p.line_spacing = line_spacing
        r = p.add_run()
        r.text = line
        r.font.name = FONT
        rPr = r._r.get_or_add_rPr()
        for tag in ('a:ea', 'a:cs'):
            el = rPr.find(qn(tag))
            if el is None:
                el = etree.SubElement(rPr, qn(tag))
            el.set('typeface', FONT)
        r.font.size = Pt(size)
        r.font.bold = bold
        r.font.color.rgb = color
    return box

def add_image(slide, path, x, y, w=None, h=None):
    if os.path.exists(path):
        return slide.shapes.add_picture(path, x, y, width=w, height=h)
    return None

def slide_chrome(slide, page_num=None, total=None,
                  footer="팀 왈라비 · 캘린(Calen) · 두드림 최종 결과 발표"):
    add_rect(slide, 0, 0, SW, Inches(0.08), ACCENT)
    add_text(slide, Inches(0.5), SH - Inches(0.4),
             Inches(8), Inches(0.3), footer,
             size=10, color=INK_MUTE)
    if page_num and total:
        add_text(slide, SW - Inches(1.5), SH - Inches(0.4),
                 Inches(1), Inches(0.3), f"{page_num} / {total}",
                 size=10, color=INK_MUTE, align=PP_ALIGN.RIGHT)

def section_title(slide, num, kicker, title, subtitle=None):
    add_round(slide, Inches(0.6), Inches(0.55),
              Inches(0.55), Inches(0.55), ACCENT, radius=0.35)
    add_text(slide, Inches(0.6), Inches(0.55),
             Inches(0.55), Inches(0.55), num,
             size=20, bold=True, color=WHITE,
             align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
    add_text(slide, Inches(1.3), Inches(0.55),
             Inches(8), Inches(0.3), kicker,
             size=11, bold=True, color=ACCENT)
    add_text(slide, Inches(1.3), Inches(0.8),
             Inches(11), Inches(0.7), title,
             size=30, bold=True, color=INK)
    if subtitle:
        add_text(slide, Inches(1.3), Inches(1.55),
                 Inches(11), Inches(0.4), subtitle,
                 size=14, color=INK_MUTE)
    add_rect(slide, Inches(0.6), Inches(2.05),
             Inches(12.1), Emu(9525), LINE)


TOTAL = 14
PAGE = [0]
def page(): PAGE[0] += 1; return PAGE[0]

DEMO_DIR = os.path.join(ROOT, "submission/dudream/demo")


# ============================================================
# 슬라이드 1 — 표지
# ============================================================
s = prs.slides.add_slide(BLANK)
add_rect(s, 0, 0, SW, SH, BG_SOFT)
# 우측 액센트 원
add_round(s, Inches(8), Inches(-2), Inches(8), Inches(8),
          ACCENT_SOFT, radius=0.5)
# 두드림 + 왈라비 배지
add_round(s, Inches(0.8), Inches(0.85),
          Inches(2.6), Inches(0.5), WALLABY, radius=0.4)
add_text(s, Inches(0.8), Inches(0.85),
         Inches(2.6), Inches(0.5), "두드림 프로그램 · 팀 왈라비",
         size=13, bold=True, color=WHITE,
         align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
# 프로젝트 명
add_text(s, Inches(0.8), Inches(1.7),
         Inches(10), Inches(1.5),
         "캘린 (Calen)",
         size=80, bold=True, color=INK)
add_text(s, Inches(0.8), Inches(3.4),
         Inches(11), Inches(0.6),
         "AI 기반 일정 자동 재구성 서비스",
         size=28, bold=True, color=ACCENT_DARK)
add_text(s, Inches(0.8), Inches(4.1),
         Inches(11), Inches(0.5),
         "두드림 프로그램 최종 결과 발표",
         size=15, color=INK_MUTE)

# 발표자/팀 정보
add_rect(s, Inches(0.8), Inches(5.5),
         Inches(8), Emu(9525), LINE)
add_text(s, Inches(0.8), Inches(5.7),
         Inches(8), Inches(0.4),
         "발표자: 팀장 권오영 (IT대학 컴퓨터학부)",
         size=14, bold=True, color=INK)
add_text(s, Inches(0.8), Inches(6.15),
         Inches(11), Inches(0.4),
         "팀원: 김혜진 · 최수빈 · 송채은 · 이수민 · 황영인 · 이서현",
         size=12, color=INK_SOFT)
add_text(s, Inches(0.8), Inches(6.55),
         Inches(11), Inches(0.4),
         "지도교수: 신용태 (IT대학 컴퓨터학부)   ·   2026.06.05",
         size=12, color=INK_MUTE)


# ============================================================
# 슬라이드 2 — 목차
# ============================================================
s = prs.slides.add_slide(BLANK)
slide_chrome(s, page(), TOTAL)
section_title(s, "00", "AGENDA", "목차", "오늘 다룰 내용")

contents = [
    ("01", "프로젝트 정의",       "학문적 연구 프로젝트로서의 의미"),
    ("02", "팀 구성",             "왈라비 팀 7명과 역할 분담"),
    ("03", "4단계 진행",          "12주에 걸친 마일스톤"),
    ("04", "시스템 아키텍처",     "View · ViewModel · Service 레이어"),
    ("05", "주요 화면 시연",      "실제 동작하는 캘린·통계·동물"),
    ("06", "핵심 기능 시연",      "AI 저녁 리뷰 · 초개인화 · 다국어"),
    ("07", "알고리즘 V1 → V2",   "그리디에서 양방향 탐색으로"),
    ("08", "사용자 평가",         "UT · NASA-TLX · HEART"),
    ("09", "정량 성과 · 학문 기여","4개 KPI · XAI · Human-in-loop"),
]
col_w = Inches(5.8)
row_h = Inches(0.55)
for i, (n, t, d) in enumerate(contents):
    col = i % 2; row = i // 2
    x = Inches(0.7) + col * (col_w + Inches(0.3))
    y = Inches(2.35) + row * (row_h + Inches(0.18))
    add_round(s, x, y, Inches(0.55), Inches(0.55), ACCENT_SOFT, radius=0.3)
    add_text(s, x, y, Inches(0.55), Inches(0.55), n,
             size=14, bold=True, color=ACCENT_DARK,
             align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
    add_text(s, x + Inches(0.75), y - Inches(0.02),
             col_w - Inches(0.85), Inches(0.32),
             t, size=16, bold=True, color=INK)
    add_text(s, x + Inches(0.75), y + Inches(0.28),
             col_w - Inches(0.85), Inches(0.28),
             d, size=11, color=INK_MUTE)


# ============================================================
# 슬라이드 3 — 프로젝트 정의
# ============================================================
s = prs.slides.add_slide(BLANK)
slide_chrome(s, page(), TOTAL)
section_title(s, "01", "PROJECT DEFINITION", "프로젝트 정의",
              "상용 서비스 개발이 아닌, AI · 알고리즘 · 시스템 · UX 통합 학습")

# 좌측: 한 문장 정의
add_text(s, Inches(0.6), Inches(2.4),
         Inches(7.5), Inches(0.4),
         "프로젝트 한 줄 정의", size=12, bold=True, color=ACCENT)
add_text(s, Inches(0.6), Inches(2.8),
         Inches(7.5), Inches(2.3),
         "기존 일정 관리 도구가 단순 기록 기능에 머무르는 구조적 한계를 해결하기 위해, "
         "일정 간의 맥락을 계산 가능한 형태로 모델링하고 자동으로 재구성하는 "
         "AI 기반 일정 운영 모델을 설계·실험한 프로젝트.",
         size=17, color=INK, line_spacing=1.45)

# 학습 영역 4개
add_text(s, Inches(0.6), Inches(5.05),
         Inches(7.5), Inches(0.4),
         "통합 적용한 학습 영역", size=12, bold=True, color=ACCENT)
fields = [
    ("AI 모델",  "스케줄링 알고리즘 선행 연구·설계"),
    ("알고리즘", "변수·제약·목표함수 수학적 정의"),
    ("시스템",  "View·ViewModel·Service 레이어 설계"),
    ("UX",      "사용자 평가·인지부하·HEART 측정"),
]
fy = Inches(5.45)
fw = (Inches(7.5) - Inches(0.3)) / 4
for i, (k, v) in enumerate(fields):
    x = Inches(0.6) + i * (fw + Inches(0.1))
    add_round(s, x, fy, fw, Inches(1.6), WHITE, line=LINE, radius=0.08)
    add_text(s, x, fy + Inches(0.2), fw, Inches(0.4),
             k, size=15, bold=True, color=ACCENT_DARK, align=PP_ALIGN.CENTER)
    add_text(s, x + Inches(0.15), fy + Inches(0.7),
             fw - Inches(0.3), Inches(0.8),
             v, size=10, color=INK_SOFT, align=PP_ALIGN.CENTER, line_spacing=1.3)

# 우측: 4단계 학습 과정
add_text(s, Inches(8.7), Inches(2.4),
         Inches(4.2), Inches(0.4),
         "연구 절차 4단계", size=12, bold=True, color=ACCENT)
steps = [
    ("STEP 1", "선행 연구 분석",   "스케줄링·자동화 모델 변수 정의"),
    ("STEP 2", "시스템 구조 설계", "재구성 알고리즘·데이터 흐름"),
    ("STEP 3", "실데이터 적용",    "충돌 해결 정확도·UX 변화 분석"),
    ("STEP 4", "결과 정리",         "한계·개선 방향·실험 보고서"),
]
sy = Inches(2.85)
for i, (k, t, d) in enumerate(steps):
    y = sy + i * Inches(1.0)
    add_round(s, Inches(8.7), y, Inches(4.2), Inches(0.9),
              BG_SOFT, line=LINE, radius=0.08)
    add_text(s, Inches(8.9), y + Inches(0.12),
             Inches(1.0), Inches(0.3),
             k, size=10, bold=True, color=ACCENT)
    add_text(s, Inches(8.9), y + Inches(0.36),
             Inches(3.8), Inches(0.3),
             t, size=14, bold=True, color=INK)
    add_text(s, Inches(8.9), y + Inches(0.62),
             Inches(3.8), Inches(0.3),
             d, size=10, color=INK_MUTE)


# ============================================================
# 슬라이드 4 — 팀 구성
# ============================================================
s = prs.slides.add_slide(BLANK)
slide_chrome(s, page(), TOTAL)
section_title(s, "02", "TEAM", "팀 구성",
              "팀 왈라비 — 7명, 4개 학부 협업")

team = [
    ("권오영", "팀장",  "IT대학 컴퓨터학부 4학년",  "전체 아키텍처 · Mac/iOS 개발 · UX 목적 정의 · 디자인씽킹"),
    ("김혜진", "팀원",  "인문대학 문예창작학부 4학년", "PRD · 명세서 · KPI 대시보드 · HEART · 마케팅 방향성"),
    ("최수빈", "팀원",  "IT대학 컴퓨터학부 4학년",  "Calendar API · OAuth · 양방향 동기화 · 통합 예외 처리"),
    ("송채은", "팀원",  "IT대학 글로벌미디어학부 4학년", "UI 키트 · 디자인 시스템 · SEO/리텐션 · 광고 전략"),
    ("이수민", "팀원",  "IT대학 글로벌미디어학부 3학년", "와이어프레임 · Figma · UT · 디자인 시스템 매핑"),
    ("황영인", "팀원",  "IT대학 글로벌미디어학부 4학년", "User Flow · 평가 구조 설계 · UT 진행 · UX 평가 보고서"),
    ("이서현", "팀원",  "AI대학 AI 융합학부 4학년",  "알고리즘 V1/V2 · 충돌 탐지 · Cost Function · 양방향 탐색"),
]
# 4 + 3 배치
def member_card(x, y, w, h, name, role, dept, work):
    add_round(s, x, y, w, h, WHITE, line=LINE, radius=0.06)
    role_color = WALLABY if role == "팀장" else ACCENT
    add_round(s, x + Inches(0.2), y + Inches(0.2),
              Inches(0.7), Inches(0.35), role_color, radius=0.3)
    add_text(s, x + Inches(0.2), y + Inches(0.2),
             Inches(0.7), Inches(0.35), role,
             size=10, bold=True, color=WHITE,
             align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
    add_text(s, x + Inches(1.0), y + Inches(0.2),
             w - Inches(1.1), Inches(0.35),
             name, size=18, bold=True, color=INK)
    add_text(s, x + Inches(0.2), y + Inches(0.65),
             w - Inches(0.3), Inches(0.3),
             dept, size=10, color=INK_MUTE)
    add_text(s, x + Inches(0.2), y + Inches(0.98),
             w - Inches(0.3), h - Inches(1.1),
             work, size=10, color=INK_SOFT, line_spacing=1.4)

cw = Inches(3.0); ch = Inches(2.0)
# 1행 4명
for i, m in enumerate(team[:4]):
    x = Inches(0.6) + i * (cw + Inches(0.15))
    member_card(x, Inches(2.4), cw, ch, *m)
# 2행 3명 (가운데 정렬)
total_w = 3 * cw + 2 * Inches(0.15)
start_x = (SW - total_w) / 2
for i, m in enumerate(team[4:]):
    x = start_x + i * (cw + Inches(0.15))
    member_card(x, Inches(4.55), cw, ch, *m)

# 지도교수
add_text(s, Inches(0.6), Inches(6.75),
         Inches(12), Inches(0.4),
         "지도교수  ·  신용태 (IT대학 컴퓨터학부)   |   소속  ·  숭실대학교",
         size=11, bold=True, color=INK_MUTE, align=PP_ALIGN.CENTER)


# ============================================================
# 슬라이드 5 — 4단계 진행
# ============================================================
s = prs.slides.add_slide(BLANK)
slide_chrome(s, page(), TOTAL)
section_title(s, "03", "TIMELINE", "4단계 진행",
              "12주 — 기획·설계 → 프로토타입·연동 → 구현·검증 → 평가·고도화")

phases = [
    ("1-3주차", "92%",  "기획·설계 기반",
     "PRD 초안 · IA / User Flow · 와이어프레임\n"
     "Google Calendar API / OAuth 조사\n"
     "알고리즘 변수·제약·의사코드 정의"),
    ("4-6주차", "93%",  "프로토타입·연동",
     "홈 / 캘린더 / 리스트 핵심 화면 구현\n"
     "OAuth 토큰 · 캘린더 읽기 PoC\n"
     "충돌 탐지 · 후보 생성 · 평가 지표"),
    ("7-9주차", "95%",  "구현·검증·확장",
     "Mac 데모 안정화 · 10인 UT\n"
     "양방향 동기화 · 통합 예외 처리\n"
     "iOS·iPad 착수 · 공유 레이어"),
    ("10-12주차", "95%", "UX 검증·V2·최종",
     "UT 2차 · NASA-TLX · 5점 척도\n"
     "알고리즘 V2 (양방향+Soft Penalty)\n"
     "최종 KPI 도출 · 보고서 마무리"),
]
px = Inches(0.6); py = Inches(2.4)
pw = (SW - Inches(1.2) - Inches(0.3)) / 4
ph = Inches(4.2)

for i, (when, pct, title, body) in enumerate(phases):
    x = px + i * (pw + Inches(0.1))
    add_round(s, x, py, pw, ph, WHITE, line=LINE, radius=0.06)
    # 단계 헤더 (액센트 띠)
    add_round(s, x, py, pw, Inches(0.7),
              ACCENT_DARK if i < 3 else SUCCESS, radius=0.06)
    add_text(s, x, py + Inches(0.08),
             pw, Inches(0.3), when,
             size=11, bold=True, color=WHITE, align=PP_ALIGN.CENTER)
    add_text(s, x, py + Inches(0.35),
             pw, Inches(0.3), f"평균 달성도 {pct}",
             size=10, color=WHITE, align=PP_ALIGN.CENTER)
    # 단계 제목
    add_text(s, x + Inches(0.2), py + Inches(0.9),
             pw - Inches(0.4), Inches(0.5),
             title, size=15, bold=True, color=INK)
    # 본문
    add_text(s, x + Inches(0.2), py + Inches(1.5),
             pw - Inches(0.4), ph - Inches(1.7),
             body, size=10, color=INK_SOFT, line_spacing=1.5)

# 하단 코멘트
add_text(s, Inches(0.6), Inches(6.8),
         Inches(12), Inches(0.3),
         "지도교수 의견 — 매 주차 적절하게 개발이 진행되고 있음을 확인",
         size=11, bold=True, color=INK_MUTE, align=PP_ALIGN.CENTER)


# ============================================================
# 슬라이드 6 — 시스템 아키텍처
# ============================================================
s = prs.slides.add_slide(BLANK)
slide_chrome(s, page(), TOTAL)
section_title(s, "04", "ARCHITECTURE", "시스템 아키텍처",
              "Swift Package 단일 모듈 → Mac · iOS · iPad 공유 레이어 확장")

# 좌측: 4단 레이어
add_text(s, Inches(0.6), Inches(2.4),
         Inches(7), Inches(0.4),
         "레이어 아키텍처", size=12, bold=True, color=ACCENT)

layers = [
    ("View Layer",      "MainView · CalendarGridView · ChatView · ReviewView", ACCENT_SOFT),
    ("ViewModel Layer", "CalendarViewModel (@MainActor) — 상태 통합 관리",     WHITE),
    ("Service Layer",   "GoogleAuth · GoogleCalendar · AIService\n"
                        "SmartScheduler · ReviewAI · UserContext · Goal",      WHITE),
    ("External",        "Google Calendar API · EventKit · Local CLI · Keychain", ACCENT_SOFT),
]
ay = Inches(2.85)
for i, (k, v, bg) in enumerate(layers):
    h = Inches(1.0) if i == 2 else Inches(0.75)
    add_round(s, Inches(0.6), ay, Inches(7.0), h,
              bg, line=LINE if bg == WHITE else None, radius=0.08)
    add_text(s, Inches(0.85), ay + Inches(0.1),
             Inches(2.5), Inches(0.3),
             k, size=11, bold=True, color=ACCENT_DARK)
    add_text(s, Inches(0.85), ay + Inches(0.38),
             Inches(6.5), h - Inches(0.4),
             v, size=12, color=INK, line_spacing=1.4)
    ay += h + Inches(0.1)

# 우측: 멀티플랫폼
add_text(s, Inches(8.0), Inches(2.4),
         Inches(4.8), Inches(0.4),
         "멀티플랫폼 확장", size=12, bold=True, color=ACCENT)

plats = [
    ("Mac",  "0.0.1 → 0.3.80+", "채팅 · 만다라트 · Google Calendar · 테마 · 동물"),
    ("iOS",  "착수 (9주차~)",   "MonthGrid · DayDetail · Chat · OAuth · Today Replan"),
    ("iPad", "공유 레이어",      "CalenShared · TimeGridLayout · WidgetKit"),
]
py2 = Inches(2.85)
for i, (k, ver, desc) in enumerate(plats):
    y = py2 + i * Inches(1.05)
    add_round(s, Inches(8.0), y, Inches(4.8), Inches(0.95),
              BG_SOFT, line=LINE, radius=0.08)
    add_round(s, Inches(8.2), y + Inches(0.2),
              Inches(0.9), Inches(0.55), ACCENT, radius=0.2)
    add_text(s, Inches(8.2), y + Inches(0.2),
             Inches(0.9), Inches(0.55), k,
             size=13, bold=True, color=WHITE,
             align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
    add_text(s, Inches(9.2), y + Inches(0.15),
             Inches(3.5), Inches(0.3),
             ver, size=11, bold=True, color=ACCENT_DARK)
    add_text(s, Inches(9.2), y + Inches(0.45),
             Inches(3.5), Inches(0.4),
             desc, size=10, color=INK_SOFT)


# ============================================================
# 슬라이드 7 — 주요 화면 시연
# ============================================================
s = prs.slides.add_slide(BLANK)
slide_chrome(s, page(), TOTAL)
section_title(s, "05", "DEMO 1", "주요 화면 시연",
              "실제 동작하는 캘린의 메인 인터페이스 — 다크 모드 + 픽셀 동물")

# 좌측 큰 이미지: 메인 캘린더 (월간 + 통계 사이드 + 우측 일정)
main_img = os.path.join(DEMO_DIR, "01_main_calendar.png")
add_round(s, Inches(0.6), Inches(2.4),
          Inches(8.4), Inches(4.7), WHITE, line=LINE, radius=0.05)
add_image(s, main_img, Inches(0.7), Inches(2.5),
          w=Inches(8.2))

# 우측: 캡션 + 핵심 기능 리스트
add_text(s, Inches(9.3), Inches(2.4),
         Inches(3.6), Inches(0.4),
         "메인 화면", size=12, bold=True, color=ACCENT)
add_text(s, Inches(9.3), Inches(2.75),
         Inches(3.6), Inches(0.6),
         "통계 + 월간 캘린더 + 일정 패널",
         size=16, bold=True, color=INK, line_spacing=1.3)

# 기능 포인트
points = [
    ("📊", "통계 패널",
     "오늘·이번주·달·연도 달성률,\n30일 잔디 그리드 (207/717)"),
    ("📅", "월간 통합 캘린더",
     "Google Calendar 연동,\n색상별 카테고리·D-day"),
    ("📋", "일일 일정 패널",
     "오늘 일정·다가오는 마감,\n로봇수업·대학원 서류 등"),
    ("🐾", "픽셀 동물 (감성 요소)",
     "코알라·고양이·강아지 등\n진행도에 따라 등장"),
]
ly = Inches(3.6)
for i, (icon, t, d) in enumerate(points):
    y = ly + i * Inches(0.85)
    add_text(s, Inches(9.3), y, Inches(0.4), Inches(0.4),
             icon, size=18, color=ACCENT)
    add_text(s, Inches(9.7), y, Inches(3.3), Inches(0.3),
             t, size=12, bold=True, color=INK)
    add_text(s, Inches(9.7), y + Inches(0.27),
             Inches(3.3), Inches(0.5),
             d, size=10, color=INK_SOFT, line_spacing=1.3)


# ============================================================
# 슬라이드 8 — 핵심 기능 시연 (AI 저녁 리뷰 · 초개인화 · 연동 · 다국어)
# ============================================================
s = prs.slides.add_slide(BLANK)
slide_chrome(s, page(), TOTAL)
section_title(s, "06", "DEMO 2", "핵심 기능 시연",
              "AI 저녁 리뷰 · 초개인화 컨텍스트 · 외부 연동 · 다국어 지원")

# 4분할 카드 — 각 카드에 이미지 + 캡션
demos = [
    ("AI 저녁 리뷰", "04_review.png",
     "5개의 미완료 할 일을 앞으로의 일정과 목표에 맞춰\n자동으로 재배치 — '추천대로 이동' 한 번에 적용"),
    ("AI 초개인화", "05_context.png",
     "역할·목표·현재 상황·일정 패턴을 AI가 학습\n12개 시험·자격증 자동 검색·캐싱"),
    ("외부 연동", "02_integration.png",
     "Google Calendar OAuth + Apple Calendar/Reminders\n캘린더 데이터는 기기에만 저장 (Local-first)"),
    ("다국어 지원", "06_language.png",
     "29개 언어 — 한국어·English·日本語·中文·Español\n글로벌 사용성 확보"),
]
cw = (SW - Inches(1.2) - Inches(0.3)) / 2
ch = Inches(2.3)
for i, (title, img_file, desc) in enumerate(demos):
    col = i % 2; row = i // 2
    x = Inches(0.6) + col * (cw + Inches(0.15))
    y = Inches(2.4) + row * (ch + Inches(0.15))
    add_round(s, x, y, cw, ch, WHITE, line=LINE, radius=0.06)
    # 좌측: 이미지
    img_path = os.path.join(DEMO_DIR, img_file)
    if os.path.exists(img_path):
        from PIL import Image as PILImg
        im = PILImg.open(img_path)
        iw, ih = im.size
        # 이미지 영역
        img_box_w = Inches(2.1)
        img_box_h = ch - Inches(0.4)
        scale = min(float(img_box_w) / iw, float(img_box_h) / ih)
        nw = iw * scale; nh = ih * scale
        px = x + Inches(0.2) + (img_box_w - nw) / 2
        py = y + Inches(0.2) + (img_box_h - nh) / 2
        add_image(s, img_path, px, py, w=nw, h=nh)
    # 우측: 타이틀 + 설명
    tx = x + Inches(2.5)
    add_text(s, tx, y + Inches(0.25),
             cw - Inches(2.6), Inches(0.4),
             title, size=15, bold=True, color=INK)
    add_text(s, tx, y + Inches(0.75),
             cw - Inches(2.6), ch - Inches(0.9),
             desc, size=11, color=INK_SOFT, line_spacing=1.5)


# ============================================================
# 슬라이드 9 — 알고리즘 V1 → V2
# ============================================================
s = prs.slides.add_slide(BLANK)
slide_chrome(s, page(), TOTAL)
section_title(s, "07", "ALGORITHM", "알고리즘 V1 → V2",
              "그리디(단방향) → 양방향 탐색 + Soft Penalty (담당: 이서현)")

# 좌: V1
v1_x = Inches(0.6); v1_w = Inches(5.9); top_y = Inches(2.4); v_h = Inches(4.2)
add_round(s, v1_x, top_y, v1_w, v_h, WHITE, line=LINE, radius=0.06)
add_round(s, v1_x, top_y, v1_w, Inches(0.6), WARN, radius=0.06)
add_text(s, v1_x, top_y + Inches(0.06),
         v1_w, Inches(0.5),
         "V1 — 단방향 그리디 (1차 실험)",
         size=15, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
         anchor=MSO_ANCHOR.MIDDLE)
v1_body = (
    "• 탐색 방향: 후방(Forward)만, 무조건 미루기\n"
    "• 제약 처리: Hard Constraint 중심\n"
    "• 실패 시 대응: 에러 반환 및 중단 (Unresolved)\n"
    "• 공간 복잡도: 큐(Queue) 1개 운용\n\n"
    "1차 실험 결과 (10개 시나리오)\n"
    "• 충돌 해결: 80% (8/10) — TC-08, TC-10 FAIL\n"
    "• 평균 지연: 35분\n"
    "• 우선순위 보존: 85%\n"
    "• 한계: 후반부 편중, 무한 루프 위험"
)
add_text(s, v1_x + Inches(0.3), top_y + Inches(0.9),
         v1_w - Inches(0.6), v_h - Inches(1.0),
         v1_body, size=12, color=INK_SOFT, line_spacing=1.5)

# 화살표
arr = s.shapes.add_shape(MSO_SHAPE.RIGHT_ARROW,
                         Inches(6.55), Inches(4.05),
                         Inches(0.35), Inches(0.5))
arr.fill.solid(); arr.fill.fore_color.rgb = ACCENT
arr.line.fill.background()

# 우: V2
v2_x = Inches(6.95); v2_w = Inches(5.9)
add_round(s, v2_x, top_y, v2_w, v_h, WHITE, line=LINE, radius=0.06)
add_round(s, v2_x, top_y, v2_w, Inches(0.6), SUCCESS, radius=0.06)
add_text(s, v2_x, top_y + Inches(0.06),
         v2_w, Inches(0.5),
         "V2 — 양방향 탐색 + Soft Penalty (2차 실험)",
         size=15, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
         anchor=MSO_ANCHOR.MIDDLE)
v2_body = (
    "• 탐색 방향: 양방향 (Forward + Backward)\n"
    "• 제약 처리: Soft Constraint + Penalty 함수\n"
    "• 실패 시 대응: 대안 제시 (Alternative Suggestion)\n"
    "• 공간 복잡도: 다중 상태 큐 (대기 / 확정)\n\n"
    "2차 실험 결과 (10개 시나리오)\n"
    "• 충돌 해결: 100% (10/10) — TC-08·10 PASS 전환\n"
    "• 평균 지연: 18분 (▼ 17분 단축)\n"
    "• 우선순위 보존: 92% (▲ +7%p)\n"
    "• 효과: Conflict-free 달성, 사용자에 유연한 대안"
)
add_text(s, v2_x + Inches(0.3), top_y + Inches(0.9),
         v2_w - Inches(0.6), v_h - Inches(1.0),
         v2_body, size=12, color=INK_SOFT, line_spacing=1.5)

# 하단 결론
add_text(s, Inches(0.6), Inches(6.85),
         Inches(12), Inches(0.3),
         "결론 — 비용 함수(Cost Function)와 양방향 탐색으로 알고리즘의 안정성과 유연성을 획기적으로 개선",
         size=11, bold=True, color=ACCENT, align=PP_ALIGN.CENTER)


# ============================================================
# 슬라이드 8 — 사용자 평가
# ============================================================
s = prs.slides.add_slide(BLANK)
slide_chrome(s, page(), TOTAL)
section_title(s, "08", "USER EVALUATION", "사용자 평가",
              "UT 10명 × 2회차 · 5점 척도 + 자유응답 + NASA-TLX + HEART")

# 좌측 — 평가 시나리오
add_text(s, Inches(0.6), Inches(2.4),
         Inches(6), Inches(0.4),
         "평가 시나리오 (5개 핵심 과업)", size=12, bold=True, color=ACCENT)
tasks = [
    "Task 1  ·  월간 캘린더에서 전체 일정 확인하기",
    "Task 2  ·  오늘 일정 확대해 빠르게 점검하기",
    "Task 3  ·  AI 채팅으로 일정 조정 요청하기",
    "Task 4  ·  AI 재계획된 일정 변경 결과 확인하기",
    "Task 5  ·  설정 및 개인화 기능 사용하기",
]
ty = Inches(2.85)
for i, t in enumerate(tasks):
    y = ty + i * Inches(0.5)
    add_round(s, Inches(0.6), y, Inches(0.3), Inches(0.3),
              ACCENT, radius=0.5)
    add_text(s, Inches(1.05), y - Inches(0.02),
             Inches(5.5), Inches(0.4),
             t, size=12, color=INK, anchor=MSO_ANCHOR.MIDDLE)

# 좌측 하단 — 정성 피드백
add_round(s, Inches(0.6), Inches(5.5),
          Inches(6), Inches(1.4), ACCENT_SOFT, radius=0.08)
add_text(s, Inches(0.85), Inches(5.6),
         Inches(5.5), Inches(0.3),
         "정성 피드백 (인터뷰 발췌)", size=10, bold=True, color=ACCENT_DARK)
add_text(s, Inches(0.85), Inches(5.9),
         Inches(5.5), Inches(0.9),
         "“AI가 멋대로 바꾸는 게 아니라 내 일정을 ‘수학적’으로\n"
         "풀어주니까 내 일정이 통제되고 있다는 느낌을 받아서 안심이 됩니다.”\n"
         "— 피험자 D (29세 직장인)",
         size=11, color=INK, line_spacing=1.4)

# 우측 — HEART 프레임워크
add_text(s, Inches(7.0), Inches(2.4),
         Inches(5.8), Inches(0.4),
         "HEART 프레임워크 (Goals · Signals · Metrics)",
         size=12, bold=True, color=ACCENT)
heart = [
    ("Happiness",   "사용자 만족 · 누름의 가벼움"),
    ("Engagement",  "콘텐츠 즐기고 계속 사용"),
    ("Adoption",    "새 사용자 채택 · 신규 기능 가치"),
    ("Retention",   "핵심 행동 위해 다시 돌아옴"),
    ("Task Success","빠르고 쉽게 완료할 수 있음"),
]
hy = Inches(2.85)
for i, (k, v) in enumerate(heart):
    y = hy + i * Inches(0.5)
    add_round(s, Inches(7.0), y, Inches(1.6), Inches(0.4),
              ACCENT, radius=0.2)
    add_text(s, Inches(7.0), y, Inches(1.6), Inches(0.4), k,
             size=11, bold=True, color=WHITE,
             align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
    add_text(s, Inches(8.75), y + Inches(0.05),
             Inches(4.2), Inches(0.35),
             v, size=11, color=INK_SOFT)

# 우측 하단 — NASA-TLX
add_round(s, Inches(7.0), Inches(5.5),
          Inches(5.8), Inches(1.4), BG_SOFT, line=LINE, radius=0.08)
add_text(s, Inches(7.2), Inches(5.6),
         Inches(5.4), Inches(0.3),
         "NASA-TLX 인지부하 측정",
         size=10, bold=True, color=ACCENT_DARK)
add_text(s, Inches(7.2), Inches(5.9),
         Inches(5.4), Inches(0.4),
         "정신적 요구  7.6점  →  3.8점   (▼ 50% 감소)",
         size=13, bold=True, color=INK)
add_text(s, Inches(7.2), Inches(6.3),
         Inches(5.4), Inches(0.4),
         "좌절 수준    5.8점  →  2.1점   (▼ 63% 감소)",
         size=13, bold=True, color=INK)


# ============================================================
# 슬라이드 9 — 정량 성과 (4 KPI)
# ============================================================
s = prs.slides.add_slide(BLANK)
slide_chrome(s, page(), TOTAL)
section_title(s, "09", "KPI RESULTS", "정량 성과 — 4개 핵심 KPI",
              "12주차 최종 도출 결과 — 모든 지표 목표치 상회")

metrics = [
    ("일정 재구성 성공률", "55%", "88%", "▲ 33%p 향상", SUCCESS,
     "수동 조정 시 이행률 → 최종 측정값"),
    ("스케줄링 의사결정 시간", "48초", "6.2초", "▼ 41.8초 단축", SUCCESS,
     "1회 의사결정 평균 소요 시간"),
    ("정신적 인지부하", "7.6점", "3.8점", "▼ 50% 인지 부하 감소", SUCCESS,
     "NASA-TLX 기준 (10점 만점)"),
    ("XAI 설명 가능성 만족도", "2.1점", "4.7점", "▲ 2.6점 신뢰도 향상", SUCCESS,
     "기존 자동화 서비스 → Calen (5점 만점)"),
]
mx = Inches(0.6); my = Inches(2.4)
mw = (SW - Inches(1.2) - Inches(0.3)) / 2; mh = Inches(2.15)

for i, (label, before, after, delta, color, sub) in enumerate(metrics):
    col = i % 2; row = i // 2
    x = mx + col * (mw + Inches(0.1))
    y = my + row * (mh + Inches(0.1))
    add_round(s, x, y, mw, mh, WHITE, line=LINE, radius=0.06)
    # 라벨
    add_text(s, x + Inches(0.25), y + Inches(0.15),
             mw - Inches(0.5), Inches(0.35),
             label, size=14, bold=True, color=INK)
    add_text(s, x + Inches(0.25), y + Inches(0.5),
             mw - Inches(0.5), Inches(0.3),
             sub, size=10, color=INK_MUTE)
    # 수치 (Before → After)
    add_text(s, x + Inches(0.25), y + Inches(0.95),
             Inches(2.2), Inches(0.7),
             before, size=28, bold=True, color=INK_MUTE,
             align=PP_ALIGN.CENTER)
    add_text(s, x + Inches(0.25), y + Inches(1.6),
             Inches(2.2), Inches(0.3),
             "기존", size=10, color=INK_MUTE, align=PP_ALIGN.CENTER)
    # 화살표
    arr = s.shapes.add_shape(MSO_SHAPE.RIGHT_ARROW,
                              x + Inches(2.55), y + Inches(1.15),
                              Inches(0.4), Inches(0.3))
    arr.fill.solid(); arr.fill.fore_color.rgb = ACCENT
    arr.line.fill.background()
    add_text(s, x + Inches(3.05), y + Inches(0.95),
             mw - Inches(3.3), Inches(0.7),
             after, size=32, bold=True, color=ACCENT,
             align=PP_ALIGN.CENTER)
    add_text(s, x + Inches(3.05), y + Inches(1.6),
             mw - Inches(3.3), Inches(0.3),
             "Calen 적용 후", size=10, color=ACCENT, align=PP_ALIGN.CENTER, bold=True)
    # 델타 배지
    add_round(s, x + Inches(0.3), y + Inches(1.95) - Inches(0.05),
              mw - Inches(0.6), Inches(0.15) * 0,
              SUCCESS, radius=0.5)
    add_text(s, x, y + mh - Inches(0.4),
             mw, Inches(0.3),
             delta, size=12, bold=True, color=color, align=PP_ALIGN.CENTER)


# ============================================================
# 슬라이드 10 — XAI · Human-in-the-loop
# ============================================================
s = prs.slides.add_slide(BLANK)
slide_chrome(s, page(), TOTAL)
section_title(s, "10", "ACADEMIC CONTRIBUTION", "XAI · Human-in-the-loop",
              "본 프로젝트의 가장 큰 학문적 기여")

# 두 개의 큰 카드
cards = [
    ("01", "설명 가능 AI (XAI)의 UX적 구현",
     "AI가 수행한 결과만 보여주지 않고, '이동 시간 부족', '우선순위 낮음' 등의 "
     "근거 메시지와 Before/After 대조 레이아웃을 함께 제공한 것이 "
     "신뢰도 향상의 핵심 요인임을 데이터로 입증.",
     "XAI 만족도\n2.1 → 4.7점",
     ACCENT),
    ("02", "Human-in-the-loop 모델의 유효성 검증",
     "최종 확정 권한을 사용자에게 부여하는 인터랙션(승인/거부)을 통해, "
     "자동화 시스템에서 발생하던 거부감을 완화하고 서비스 수용성을 극대화. "
     "AI 판단 + 인간 결정 = 신뢰 가능한 자동화.",
     "재구성 성공률\n55% → 88%",
     WALLABY),
]
cx = Inches(0.6); cy = Inches(2.4); cw = Inches(6.05); ch = Inches(4.3)
for i, (num, t, body, badge, color) in enumerate(cards):
    x = cx + i * (cw + Inches(0.2))
    add_round(s, x, cy, cw, ch, WHITE, line=LINE, radius=0.06)
    # 좌측 번호 띠
    add_round(s, x, cy, Inches(0.5), ch, color, radius=0.06)
    add_text(s, x, cy + Inches(0.25),
             Inches(0.5), Inches(0.5),
             num, size=18, bold=True, color=WHITE,
             align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
    # 타이틀
    add_text(s, x + Inches(0.7), cy + Inches(0.25),
             cw - Inches(0.9), Inches(0.9),
             t, size=18, bold=True, color=INK, line_spacing=1.3)
    # 본문
    add_text(s, x + Inches(0.7), cy + Inches(1.4),
             cw - Inches(0.9), Inches(1.7),
             body, size=12, color=INK_SOFT, line_spacing=1.5)
    # 결과 배지
    add_round(s, x + Inches(0.7), cy + ch - Inches(1.05),
              cw - Inches(1.4), Inches(0.85), BG_SOFT,
              line=LINE, radius=0.08)
    add_text(s, x + Inches(0.7), cy + ch - Inches(1.0),
             cw - Inches(1.4), Inches(0.8),
             badge, size=14, bold=True, color=color,
             align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE, line_spacing=1.2)

# 하단 강조
add_text(s, Inches(0.6), Inches(6.85),
         Inches(12), Inches(0.3),
         "이 두 발견은 향후 AI 일정 관리 분야의 설계 지침으로 활용될 수 있는 학문적 자산",
         size=11, bold=True, color=INK_MUTE, align=PP_ALIGN.CENTER)


# ============================================================
# 슬라이드 11 — 팀원별 기여 (자체평가)
# ============================================================
s = prs.slides.add_slide(BLANK)
slide_chrome(s, page(), TOTAL)
section_title(s, "11", "CONTRIBUTIONS", "팀원별 기여",
              "10-12주차 자체평가 — 7명 전원의 핵심 산출물")

contribs = [
    ("권오영 (팀장)",
     "Mac/iOS·PC 통합 환경 UX 정의 · 디자인씽킹 프로세스 팀 내 도입 · 전체 시스템 아키텍처 안정화"),
    ("김혜진",
     "알고리즘 V1 vs V2 비교 보고서 · 메타광고 기획 · Mobile/PC 플랫폼별 브랜딩 차별화 전략"),
    ("최수빈",
     "Google Calendar API 연동 구조 재설계 · OAuth 안정화 · 이벤트 정규화 파이프라인 · 통합 예외 처리"),
    ("송채은",
     "UI/UX 개념·심리학 원칙 디자인 적용 · 시스템 안정성 개선 구조 · SEO·리텐션·광고 전략"),
    ("이수민",
     "사용성 테스트(UT) 시나리오 설계 · Figma 핸드오프 자산화 · Mobile/PC 디자인 시스템 매핑"),
    ("황영인",
     "사용자 평가 구조 설계 → 10명 실사용 검증 → UX 평가 보고서 · MAU 성장 전략 종합 정리"),
    ("이서현",
     "9주차 V1 한계 분석 → 양방향 탐색 + Soft Penalty 적용 V2 설계·구현 · 1차 FAIL 케이스 전원 PASS · 충돌 해결 80%→100%"),
]
ty = Inches(2.4); rh = Inches(0.62)
for i, (name, work) in enumerate(contribs):
    y = ty + i * rh
    add_round(s, Inches(0.6), y, Inches(2.5), Inches(0.5),
              ACCENT_SOFT, radius=0.2)
    add_text(s, Inches(0.6), y, Inches(2.5), Inches(0.5), name,
             size=12, bold=True, color=ACCENT_DARK,
             align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
    add_text(s, Inches(3.25), y + Inches(0.08),
             Inches(9.5), Inches(0.4),
             work, size=11, color=INK_SOFT)


# ============================================================
# 슬라이드 12 — Thank You
# ============================================================
s = prs.slides.add_slide(BLANK)
add_rect(s, 0, 0, SW, SH, ACCENT)
add_round(s, Inches(9), Inches(-2), Inches(8), Inches(8),
          ACCENT_DARK, radius=0.5)
add_text(s, Inches(0.8), Inches(2.2),
         Inches(11), Inches(1.5),
         "Thank You",
         size=84, bold=True, color=WHITE)
add_text(s, Inches(0.8), Inches(4.0),
         Inches(11), Inches(0.6),
         "감사합니다",
         size=32, bold=True, color=WHITE)
add_text(s, Inches(0.8), Inches(5.0),
         Inches(11), Inches(0.5),
         "팀 왈라비  ·  캘린(Calen)  ·  AI 기반 일정 자동 재구성 서비스",
         size=16, color=ACCENT_SOFT)
add_text(s, Inches(0.8), Inches(6.3),
         Inches(11), Inches(0.4),
         "권오영 · 김혜진 · 최수빈 · 송채은 · 이수민 · 황영인 · 이서현",
         size=12, color=ACCENT_SOFT)
add_text(s, Inches(0.8), Inches(6.75),
         Inches(11), Inches(0.4),
         "지도교수: 신용태 (IT대학 컴퓨터학부)  ·  2026.06.05",
         size=11, color=ACCENT_SOFT)


# ---------- 저장 ---------- #
prs.save(OUT)
print(f"saved: {OUT}")
print(f"slides: {len(prs.slides)}")
print(f"size: {os.path.getsize(OUT)/1024:.1f} KB")
