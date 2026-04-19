#if os(iOS)
import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var facts: [MemoryFactRecord]

    var body: some View {
        NavigationStack {
            List {
                Section("계정") {
                    LabelRow(icon: "person.circle.fill", title: "Google 로그인", detail: "연결 필요")
                        .foregroundStyle(.secondary)
                }

                Section("동기화") {
                    LabelRow(icon: "icloud.fill", title: "iCloud 동기화",
                             detail: "활성 — \(facts.count)개 기억")
                        .foregroundStyle(.blue)
                    Text("macOS/iPad와 같은 Apple ID면 자동으로 데이터가 공유됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("앱 정보") {
                    LabelRow(icon: "info.circle", title: "버전", detail: "0.3.1 (iOS beta)")
                    Link(destination: URL(string: "https://oyeong011.github.io/Planit/")!) {
                        LabelRow(icon: "link", title: "공식 사이트", detail: "")
                    }
                }
            }
            .navigationTitle("설정")
        }
    }
}

struct LabelRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
