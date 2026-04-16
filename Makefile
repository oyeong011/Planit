.PHONY: dev kill run build

# 개발 빌드 + 재시작 (가장 자주 쓰는 명령)
dev:
	pkill -f "Calen.app/Contents/MacOS/Calen" 2>/dev/null || true
	bash scripts/run-dev.sh

# 앱만 종료
kill:
	pkill -f "Calen.app/Contents/MacOS/Calen" 2>/dev/null || true
	@echo "Calen stopped"

# 빌드 없이 재시작만 (코드 변경 없을 때)
run:
	pkill -f "Calen.app/Contents/MacOS/Calen" 2>/dev/null || true
	open /tmp/Calen.app

# 릴리즈 빌드
build:
	bash scripts/build-app.sh $(VERSION)

# 테스트
test:
	swift test
