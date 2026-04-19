# 로컬라이제이션 누락 보고서 (v0.3.3)

스크립트: `./scripts/verify-localizations.sh`

base는 `ko.lproj/Localizable.strings` 입니다. 아래 키가 29개 모든 언어에서 누락되어 있습니다.

## 누락된 키 + ko 원문

- `"chat.action.unknown"` → "chat.action.unknown" = "(알 수 없는 일정)";
- `"settings.ai.tone.card"` → "settings.ai.tone.card" = "응답 톤";
- `"settings.ai.tone.coaching.desc"` → "settings.ai.tone.coaching.desc" = "목표와 에너지 흐름을 함께 설명합니다.";
- `"settings.ai.tone.coaching"` → "settings.ai.tone.coaching" = "코칭";
- `"settings.ai.tone.concise.desc"` → "settings.ai.tone.concise.desc" = "다음 행동 중심으로 짧게 답합니다.";
- `"settings.ai.tone.concise"` → "settings.ai.tone.concise" = "간결";
- `"settings.ai.tone.direct.desc"` → "settings.ai.tone.direct.desc" = "우선순위와 실행안을 바로 말합니다.";
- `"settings.ai.tone.direct"` → "settings.ai.tone.direct" = "직접";
- `"settings.appearance.subtitle"` → "settings.appearance.subtitle" = "Calen의 표시 방식과 캘린더 색상을 설정합니다";
- `"settings.apple.diagnostics.accessibility"` → "settings.apple.diagnostics.accessibility" = "Apple 캘린더 진단. 중복 필터 적용: external ID %d건, fingerprint %d건, suppress %d건. 마지막 업데이트 %@.";
- `"settings.apple.diagnostics.card"` → "settings.apple.diagnostics.card" = "Apple 캘린더 진단";
- `"settings.apple.diagnostics.help"` → "settings.apple.diagnostics.help" = "동일 이벤트가 Google과 Apple 양쪽에 있을 때 자동 제거된 수";
- `"settings.apple.diagnostics.never"` → "settings.apple.diagnostics.never" = "없음";
- `"settings.apple.diagnostics.summary"` → "settings.apple.diagnostics.summary" = "중복 필터 적용: ext %d / fingerprint %d / suppress %d · 마지막 업데이트 %@";
- `"settings.focus.windows.card"` → "settings.focus.windows.card" = "집중 시간 기반 배치";
- `"settings.focus.windows.desc"` → "settings.focus.windows.desc" = "AI가 빈 시간을 고를 때 아침형/저녁형 선호를 먼저 반영합니다.";
- `"settings.focus.windows.title"` → "settings.focus.windows.title" = "에너지 타입 기반 집중 시간대 사용";
- `"settings.section.appearance"` → "settings.section.appearance" = "외관";

## 처리 방법

1. 각 언어 파일에 위 키를 `= "translated value";` 형식으로 추가
2. 임시 대응: 영어 버전을 fallback으로 사용
3. `./scripts/verify-localizations.sh` 돌려서 0개 되는지 재확인

## 우선순위 언어

- **en, ja, zh-Hans, zh-Hant**: 주요 시장
- **es, fr, de, pt-BR, ru**: 대형 로컬
- **나머지 21개**: 기본 영어 복사도 수용 가능

