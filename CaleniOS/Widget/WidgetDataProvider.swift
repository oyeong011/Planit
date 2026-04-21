// MARK: - WidgetDataProvider
//
// App Group으로 공유된 오늘의 이벤트 스냅샷을 위젯이 읽어오는 진입점.
//
// 우선순위:
//   1) `UserDefaults(suiteName: group.com.oy.planit)` — 가벼운 페이로드에 적합.
//   2) App Group 컨테이너 내 `widget-events.json` 파일 fallback — UserDefaults 용량
//      한도(~4MB) 초과 대비 또는 위젯-앱 동시 write 경합 회피용.
//
// 둘 다 실패하면 빈 배열 반환 — 위젯은 이때 "일정이 없어요" empty state를 보여준다.

import Foundation

public enum WidgetDataProvider {

    // MARK: Public API

    /// 위젯이 타임라인 구성 시 호출. 오늘 이후(=`now` 이후 종료)의 이벤트만 필터 + 정렬.
    public static func loadUpcomingEvents(
        now: Date = Date(),
        limit: Int = 4
    ) -> [EventSnapshot] {
        let bundle = loadBundle()
        return bundle?.events
            .filter { $0.end >= now }          // 이미 끝난 이벤트 제외
            .sorted { $0.start < $1.start }
            .prefix(limit)
            .map { $0 } ?? []
    }

    /// 전체 번들 로드. publishedAt 등 메타정보까지 필요한 테스트/진단용.
    public static func loadBundle() -> EventSnapshotBundle? {
        if let fromDefaults = loadFromUserDefaults() {
            return fromDefaults
        }
        if let fromFile = loadFromFile() {
            return fromFile
        }
        return nil
    }

    // MARK: UserDefaults path

    private static func loadFromUserDefaults() -> EventSnapshotBundle? {
        guard let defaults = UserDefaults(suiteName: EventSnapshotBundle.appGroupIdentifier) else {
            return nil
        }
        guard let data = defaults.data(forKey: EventSnapshotBundle.userDefaultsKey) else {
            return nil
        }
        return try? EventSnapshotBundle.makeDecoder().decode(EventSnapshotBundle.self, from: data)
    }

    // MARK: File path

    /// App Group container 내의 `widget-events.json` URL.
    /// Portal 등록 전이거나 entitlement 누락 시 nil.
    public static func fileURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: EventSnapshotBundle.appGroupIdentifier
        ) else {
            return nil
        }
        return containerURL.appendingPathComponent("widget-events.json", isDirectory: false)
    }

    private static func loadFromFile() -> EventSnapshotBundle? {
        guard let url = fileURL() else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? EventSnapshotBundle.makeDecoder().decode(EventSnapshotBundle.self, from: data)
    }
}
