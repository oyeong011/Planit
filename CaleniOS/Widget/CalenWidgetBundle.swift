// MARK: - CalenWidgetBundle
//
// Widget extension의 `@main` 엔트리. WidgetBundle은 동일 extension에서
// 여러 Widget을 한꺼번에 export할 수 있게 하지만, v0.1.1에선 `TodayEventsWidget`
// 1개만 포함한다. (리뷰/할일 위젯은 v0.1.2 이후 확장 예정.)

import WidgetKit
import SwiftUI

@main
struct CalenWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayEventsWidget()
    }
}
