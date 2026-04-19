#if os(iOS)
import Foundation
import SwiftData
import Combine

// MARK: - HomeViewModel
//
// 레퍼런스 `Calen-iOS/Calen/Features/Home/HomeViewModel.swift` 1:1 포팅 (M2 UI v3).

// MARK: - ScheduleDisplayItem
// A lightweight, view-ready value type derived from the SwiftData Schedule model.

struct ScheduleDisplayItem: Identifiable {
    let id: UUID
    let title: String
    let category: ScheduleCategory
    let startTime: Date
    let endTime: Date?
    let location: String?
    let summary: String?
    let travelTimeMinutes: Int?
    let bulletPoints: [String]

    // Initialise from a SwiftData model object
    init(from schedule: Schedule) {
        self.id = schedule.id
        self.title = schedule.title
        self.category = schedule.category
        self.startTime = schedule.startTime
        self.endTime = schedule.endTime
        self.location = schedule.location
        self.summary = schedule.summary
        self.travelTimeMinutes = schedule.travelTimeMinutes

        if let notes = schedule.notes, !notes.isEmpty {
            self.bulletPoints = notes
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } else {
            self.bulletPoints = []
        }
    }

    // Direct initialiser used for mock / preview data
    init(
        id: UUID = UUID(),
        title: String,
        category: ScheduleCategory,
        startTime: Date,
        endTime: Date? = nil,
        location: String? = nil,
        summary: String? = nil,
        travelTimeMinutes: Int? = nil,
        bulletPoints: [String] = []
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.summary = summary
        self.travelTimeMinutes = travelTimeMinutes
        self.bulletPoints = bulletPoints
    }
}

// MARK: - HomeViewModel

@MainActor
final class HomeViewModel: ObservableObject {

    // MARK: Published state

    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @Published var schedules: [ScheduleDisplayItem] = []
    @Published var weekDates: [Date] = []

    // MARK: Internal – injected after view appears

    var modelContext: ModelContext?

    // MARK: Init

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        generateWeekDates(around: selectedDate)
        fetchSchedules()
    }

    // MARK: Public API

    func selectDate(_ date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
        generateWeekDates(around: selectedDate)
        fetchSchedules()
    }

    func fetchSchedules() {
        guard let context = modelContext else {
            schedules = Self.mockSchedules(for: selectedDate)
            return
        }

        let start = Calendar.current.startOfDay(for: selectedDate)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }

        let predicate = #Predicate<Schedule> { $0.date >= start && $0.date < end }
        let descriptor = FetchDescriptor<Schedule>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startTime)]
        )

        do {
            let results = try context.fetch(descriptor)
            schedules = results.map { ScheduleDisplayItem(from: $0) }
        } catch {
            print("[HomeViewModel] fetchSchedules error: \(error)")
            schedules = []
        }
    }

    // MARK: Week strip helpers

    private func generateWeekDates(around date: Date) {
        let calendar = Calendar.current
        // Anchor to the Monday of the current ISO week
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        comps.weekday = 2 // Monday = 2 in ISO calendar
        guard let monday = calendar.date(from: comps) else { return }
        weekDates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    // MARK: Mock / preview data

    static func mockSchedules(for date: Date) -> [ScheduleDisplayItem] {
        let cal = Calendar.current

        func t(_ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }

        return [
            ScheduleDisplayItem(
                title: "직장",
                category: .work,
                startTime: t(8),
                endTime: t(12),
                location: "서울 강남구 테헤란로 123",
                summary: nil,
                travelTimeMinutes: nil,
                bulletPoints: [
                    "주간 팀 미팅 준비",
                    "보고서 초안 작성",
                    "코드 리뷰 완료"
                ]
            ),
            ScheduleDisplayItem(
                title: "거래처 회의",
                category: .meeting,
                startTime: t(14),
                endTime: t(15, 30),
                location: "강남역 인근 카페",
                summary: "신규 프로젝트 제안 및 계약 조건 협의",
                travelTimeMinutes: 20,
                bulletPoints: []
            ),
            ScheduleDisplayItem(
                title: "저녁식사",
                category: .meal,
                startTime: t(18),
                endTime: t(19, 30),
                location: "삼성동 맛집",
                summary: "팀원들과 프로젝트 완료 축하 식사",
                travelTimeMinutes: 15,
                bulletPoints: []
            )
        ]
    }
}
#endif
