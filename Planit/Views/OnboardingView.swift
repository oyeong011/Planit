import SwiftUI

struct OnboardingView: View {
    @ObservedObject var goalService: GoalService
    let onComplete: () -> Void
    let onSkip: (() -> Void)?

    init(goalService: GoalService, onComplete: @escaping () -> Void, onSkip: (() -> Void)? = nil) {
        self.goalService = goalService
        self.onComplete = onComplete
        self.onSkip = onSkip
    }

    @State private var goalInputs: [(String, Date)] = []
    @State private var newGoalTitle = ""
    @State private var newGoalDate = Calendar.current.date(byAdding: .month, value: 6, to: Date())!

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header
            headerBar

            Divider()

            // MARK: Content
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 20)

                    goalsStep

                    Spacer().frame(height: 20)
                }
            }

            Divider()

            // MARK: Navigation footer
            navigationFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 0) {
            // Title
            Text(String(localized: "onboarding.title"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            // Close / X button
            Button {
                if let skip = onSkip {
                    skip()
                } else {
                    onComplete()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(Color(.controlBackgroundColor))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .allowsHitTesting(true)
    }

    // MARK: - Navigation Footer

    private var navigationFooter: some View {
        HStack(spacing: 0) {
            // 나중에 설정 버튼
            Button {
                if let skip = onSkip {
                    skip()
                } else {
                    onComplete()
                }
            } label: {
                Text(String(localized: "common.skip"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .allowsHitTesting(true)

            Spacer()

            // 시작 버튼
            Button {
                completeOnboarding()
            } label: {
                Text(String(localized: "onboarding.start"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.purple)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .allowsHitTesting(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .allowsHitTesting(true)
    }

    // MARK: - Step 0: Goals

    private var goalsStep: some View {
        VStack(alignment: .center, spacing: 14) {
            stepHeader(
                icon: "target",
                title: String(localized: "onboarding.goals.title"),
                subtitle: String(localized: "onboarding.goals.subtitle")
            )

            // Added goals list
            if !goalInputs.isEmpty {
                VStack(spacing: 5) {
                    ForEach(goalInputs.indices, id: \.self) { i in
                        goalChip(index: i)
                    }
                }
            }

            // Input card
            if goalInputs.count < 3 {
                VStack(spacing: 8) {
                    TextField(String(localized: "onboarding.goals.placeholder"), text: $newGoalTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(.textBackgroundColor).opacity(0.6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                )
                        )

                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text(String(localized: "onboarding.goals.target.date"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            DatePicker("", selection: $newGoalDate, displayedComponents: .date)
                                .labelsHidden()
                                .controlSize(.mini)
                        }

                        Spacer()

                        Button {
                            guard !newGoalTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            goalInputs.append((newGoalTitle.trimmingCharacters(in: .whitespaces), newGoalDate))
                            newGoalTitle = ""
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .bold))
                                Text(String(localized: "common.add"))
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(newGoalTitle.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.purple)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .disabled(newGoalTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                        .allowsHitTesting(true)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color(.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                        )
                )
            }

            // Preset chips (only when list is empty)
            if goalInputs.isEmpty {
                VStack(spacing: 6) {
                    Text(String(localized: "onboarding.goals.quick.select"))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 5) {
                        presetChip(String(localized: "onboarding.goals.preset.certification"))
                        presetChip(String(localized: "onboarding.goals.preset.sideproject"))
                        presetChip(String(localized: "onboarding.goals.preset.health"))
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
    }

    private func goalChip(index i: Int) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.purple.opacity(0.8))
                .frame(width: 5, height: 5)

            Text(goalInputs[i].0)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            Spacer()

            Text(shortDate(goalInputs[i].1))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Button {
                goalInputs.remove(at: i)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.purple.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.purple.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private func presetChip(_ title: String) -> some View {
        Button {
            newGoalTitle = title
        } label: {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(true)
    }

    // MARK: - Shared Step Header

    private func stepHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.purple)
            }

            Text(title)
                .font(.system(size: 14, weight: .bold))
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Complete

    private func completeOnboarding() {
        // 기본값 설정 (설정 화면에서 나중에 변경 가능)
        goalService.profile.workStartHour = 9
        goalService.profile.workEndHour = 18
        goalService.profile.commuteMinutes = 30
        goalService.profile.energyType = .balanced
        goalService.profile.weekdayCapacityMinutes = 480
        goalService.profile.weekendCapacityMinutes = 480

        for (title, due) in goalInputs {
            // 온보딩에서 받는 목표는 대부분 장기성(대학원, 취업, 자격증 등).
            // 주간 반복 스케줄(recurrence)를 자동으로 붙이지 않음 — 붙이면 매일
            // "이번주 0/4회, 20시에 60분?" 알림이 뜨는 UX 문제 발생.
            // 반복 활동은 별도 '습관' 기능으로 추가하게 안내.
            let goal = Goal(
                level: .year,
                title: title,
                dueDate: due,
                weight: 4,
                recurrence: nil
            )
            goalService.addGoal(goal)
        }

        goalService.profile.onboardingDone = true
        goalService.saveProfile()
        onComplete()
    }

    private func shortDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        return fmt.string(from: date)
    }
}
