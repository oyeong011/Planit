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

    @State private var step = 0
    @State private var goalInputs: [(String, Date)] = []
    @State private var newGoalTitle = ""
    @State private var newGoalDate = Calendar.current.date(byAdding: .month, value: 6, to: Date())!

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header
            headerBar

            Divider()

            // MARK: Content
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 20)

                    switch step {
                    case 0: goalsStep
                    case 1: scheduleStep
                    case 2: energyStep
                    case 3: capacityStep
                    default: EmptyView()
                    }

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

            // Step dots
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    stepDot(index: i)
                }
            }

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

    private func stepDot(index: Int) -> some View {
        let isCompleted = index < step
        let isCurrent = index == step

        return ZStack {
            if isCompleted {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 4, weight: .black))
                            .foregroundStyle(.white)
                    )
            } else if isCurrent {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 7, height: 7)
            } else {
                Circle()
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 7, height: 7)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    // MARK: - Navigation Footer

    private var navigationFooter: some View {
        HStack(spacing: 0) {
            // Previous
            if step > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { step -= 1 }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .semibold))
                        Text(String(localized: "common.previous"))
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(true)
            } else {
                // Skip link (step 0 only)
                Button {
                    if let skip = onSkip {
                        skip()
                    } else {
                        onComplete()
                    }
                } label: {
                    Text(String(localized: "common.skip"))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(true)
            }

            Spacer()

            // Step label
            Text("\(step + 1) / \(totalSteps)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Spacer()

            // Next / Start
            Button {
                if step < totalSteps - 1 {
                    withAnimation(.easeInOut(duration: 0.2)) { step += 1 }
                } else {
                    completeOnboarding()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(step == totalSteps - 1 ? String(localized: "onboarding.start") : String(localized: "common.next"))
                        .font(.system(size: 11, weight: .semibold))
                    if step < totalSteps - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
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

    // MARK: - Step 1: Schedule

    private var scheduleStep: some View {
        VStack(alignment: .center, spacing: 14) {
            stepHeader(
                icon: "clock",
                title: String(localized: "onboarding.schedule.title"),
                subtitle: String(localized: "onboarding.schedule.subtitle")
            )

            VStack(spacing: 0) {
                scheduleRow(
                    String(localized: "onboarding.schedule.work.start"),
                    value: $goalService.profile.workStartHour,
                    range: 6...12
                )
                dividerRow
                scheduleRow(
                    String(localized: "onboarding.schedule.work.end"),
                    value: $goalService.profile.workEndHour,
                    range: 15...22
                )
                dividerRow
                scheduleRow(
                    String(localized: "onboarding.schedule.lunch"),
                    value: $goalService.profile.lunchStartHour,
                    range: 11...14
                )
                dividerRow
                scheduleRow(
                    String(localized: "onboarding.schedule.commute"),
                    value: $goalService.profile.commuteMinutes,
                    range: 0...120,
                    unit: String(localized: "onboarding.schedule.unit.minute"),
                    step: 10
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 14)
    }

    private var dividerRow: some View {
        Divider()
            .padding(.horizontal, 10)
    }

    private func scheduleRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, unit: String? = nil, step: Int = 1) -> some View {
        let displayUnit = unit ?? String(localized: "onboarding.schedule.unit.hour")
        return VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(value.wrappedValue)\(displayUnit)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.purple)
                    .monospacedDigit()
                    .frame(minWidth: 36, alignment: .trailing)
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
            .controlSize(.small)
            .tint(.purple)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Step 2: Energy

    private var energyStep: some View {
        VStack(alignment: .center, spacing: 14) {
            stepHeader(
                icon: "bolt.fill",
                title: String(localized: "onboarding.energy.title"),
                subtitle: String(localized: "onboarding.energy.subtitle")
            )

            VStack(spacing: 6) {
                ForEach(EnergyType.allCases, id: \.self) { type in
                    energyOption(type)
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private func energyOption(_ type: EnergyType) -> some View {
        let selected = goalService.profile.energyType == type
        let icon: String = {
            switch type {
            case .morning: return "sunrise.fill"
            case .evening: return "moon.stars.fill"
            default:       return "equal.circle.fill"
            }
        }()
        let desc: String = {
            switch type {
            case .morning: return String(localized: "onboarding.energy.morning.desc")
            case .evening: return String(localized: "onboarding.energy.evening.desc")
            default:       return String(localized: "onboarding.energy.balanced.desc")
            }
        }()

        return Button {
            goalService.profile.energyType = type
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(selected ? Color.purple.opacity(0.12) : Color(.controlBackgroundColor))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(selected ? .purple : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(type.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(desc)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(selected ? Color.purple : Color.secondary.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                    if selected {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(selected ? Color.purple.opacity(0.06) : Color(.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(selected ? Color.purple.opacity(0.25) : Color.secondary.opacity(0.1), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
        .allowsHitTesting(true)
    }

    // MARK: - Step 3: Capacity

    private var capacityStep: some View {
        VStack(alignment: .center, spacing: 14) {
            stepHeader(
                icon: "gauge.with.dots.needle.50percent",
                title: String(localized: "onboarding.capacity.title"),
                subtitle: String(localized: "onboarding.capacity.subtitle")
            )

            // Capacity sliders card
            VStack(spacing: 0) {
                capacitySlider(String(localized: "onboarding.capacity.weekday"), value: $goalService.profile.weekdayCapacityMinutes)
                dividerRow
                capacitySlider(String(localized: "onboarding.capacity.weekend"), value: $goalService.profile.weekendCapacityMinutes)
            }
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                    )
            )

            // Aggressiveness card
            VStack(spacing: 8) {
                Text(String(localized: "onboarding.capacity.ai.level"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Picker("", selection: $goalService.profile.aggressiveness) {
                    ForEach(Aggressiveness.allCases, id: \.self) { a in
                        Text(a.rawValue).tag(a)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)

                Text(aggressivenessDesc)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
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
        .padding(.horizontal, 14)
    }

    private func capacitySlider(_ label: String, value: Binding<Int>) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                Spacer()
                Text(String(format: String(localized: "onboarding.capacity.minutes.format"), value.wrappedValue))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.purple)
                    .monospacedDigit()
                    .frame(minWidth: 40, alignment: .trailing)
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0) }
                ),
                in: 30...300,
                step: 15
            )
            .controlSize(.small)
            .tint(.purple)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var aggressivenessDesc: String {
        switch goalService.profile.aggressiveness {
        case .manual:   return String(localized: "aggressiveness.manual.desc")
        case .assist:   return String(localized: "aggressiveness.assist.desc")
        case .semiAuto: return String(localized: "aggressiveness.semiauto.desc")
        case .auto:     return String(localized: "aggressiveness.auto.desc")
        }
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
        for (title, due) in goalInputs {
            let goal = Goal(
                level: .year,
                title: title,
                dueDate: due,
                weight: 4,
                recurrence: RecurrencePlan(
                    weeklyTargetSessions: 4,
                    perSessionMinutes: 60,
                    allowedDays: [1, 2, 3, 4, 5]
                )
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
