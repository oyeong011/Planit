#if os(iOS)
import SwiftUI

// MARK: - Sync UI Components (Sprint C)
//
// 동기화/네트워크 상태와 사용자 액션 결과를 보여주는 공통 컴포넌트.
//   - SyncStatusBanner: CloudKit 오프라인/실패 시 화면 상단 노란 배지
//   - Toast: 액션 성공/실패 1.6초 띄움
//   - SkeletonLoader: 일정 로딩 시 카드 placeholder

// MARK: - SyncStatusBanner

/// CloudKit 동기화 상태가 정상이 아닐 때만 화면 상단에 노출.
struct SyncStatusBanner: View {
    let status: CloudKitSyncCoordinator.SyncStatus

    var body: some View {
        Group {
            switch status {
            case .offline:
                banner(text: "오프라인이에요. 변경사항은 연결되면 보낼게요.",
                       color: Color(hex: "#F59E0B"),
                       icon: "wifi.slash")
            case .failed(let msg):
                banner(text: "동기화 실패: \(msg)",
                       color: Color(hex: "#EF4444"),
                       icon: "exclamationmark.triangle")
            case .syncing:
                banner(text: "동기화 중…",
                       color: Color(hex: "#2B8BDA"),
                       icon: "arrow.triangle.2.circlepath")
            default:
                EmptyView()
            }
        }
    }

    private func banner(text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.white)
            Text(text)
                .font(.calenCaption)
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.95))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Toast

/// 짧은 1.6초 토스트. ZStack 최상단에 overlay 로 사용.
struct Toast: View {
    let message: String
    let kind: Kind

    enum Kind { case success, error, info
        var color: Color {
            switch self {
            case .success: return Color(hex: "#22C55E")
            case .error:   return Color(hex: "#EF4444")
            case .info:    return Color(hex: "#2B8BDA")
            }
        }
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error:   return "xmark.octagon.fill"
            case .info:    return "info.circle.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: kind.icon)
                .foregroundStyle(.white)
            Text(message)
                .font(.calenCaption)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(kind.color, in: Capsule())
        .shadow(color: kind.color.opacity(0.35), radius: 12, y: 4)
    }
}

// MARK: - Toast modifier

/// `.toast(state:)` 한 줄로 ZStack 최상단에 토스트를 띄우고 1.6초 후 자동 사라짐.
struct ToastState: Equatable {
    let id: UUID
    let message: String
    let kind: Toast.Kind

    init(_ message: String, kind: Toast.Kind = .info) {
        self.id = UUID()
        self.message = message
        self.kind = kind
    }
}

extension View {
    func toast(_ state: Binding<ToastState?>) -> some View {
        self.overlay(alignment: .top) {
            if let s = state.wrappedValue {
                Toast(message: s.message, kind: s.kind)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: s.id) {
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        withAnimation(.easeOut(duration: 0.2)) {
                            state.wrappedValue = nil
                        }
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85),
                   value: state.wrappedValue)
    }
}

// MARK: - SkeletonLoader

/// 일정 카드 로딩 placeholder. 회색 박스 + 시머 효과.
struct SkeletonCard: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(hex: "#F0F1F4"))
            .frame(height: 88)
            .overlay(shimmer)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }

    private var shimmer: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [
                    Color.white.opacity(0),
                    Color.white.opacity(0.55),
                    Color.white.opacity(0)
                ],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.5)
            .offset(x: geo.size.width * phase)
        }
    }
}

// MARK: - Preview

#Preview("Banners + Toast") {
    VStack(spacing: 12) {
        SyncStatusBanner(status: .offline)
        SyncStatusBanner(status: .syncing)
        SyncStatusBanner(status: .failed("Network unavailable"))
        Toast(message: "일정 추가 완료", kind: .success)
        Toast(message: "동기화 실패", kind: .error)
        SkeletonCard()
        SkeletonCard()
    }
    .padding()
    .background(Color(.systemBackground))
}
#endif
