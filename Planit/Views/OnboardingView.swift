import SwiftUI

struct OnboardingView: View {
    @ObservedObject var goalService: GoalService
    @State private var step = 0
    @State private var goalInputs: [(String, Date)] = []
    @State private var newGoalTitle = ""
    @State private var newGoalDate = Calendar.current.date(byAdding: .month, value: 6, to: Date())!
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(String(localized: "onboarding.title"))
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text("\(step + 1)/4")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.purple)
                        .frame(width: geo.size.width * CGFloat(step + 1) / 4.0)
                        .animation(.easeInOut(duration: 0.3), value: step)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 16)

            Divider()
                .padding(.top, 8)

            // Content
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 24)

                    switch step {
                    case 0: goalsStep
                    case 1: scheduleStep
                    case 2: energyStep
                    case 3: capacityStep
                    default: EmptyView()
                    }

                    Spacer().frame(height: 24)
                }
            }

            Divider()

            // Navigation
            HStack {
                if step > 0 {
                    Button { step -= 1 } label: {
                        Text(String(localized: "common.previous"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    if step < 3 {
                        step += 1
                    } else {
                        completeOnboarding()
                    }
                } label: {
                    Text(step == 3 ? String(localized: "onboarding.start") : String(localized: "common.next"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.purple))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Step 0: Goals

    private var goalsStep: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "target")
                .font(.system(size: 28))
                .foregroundStyle(.purple)

            Text(String(localized: "onboarding.goals.title"))
                .font(.system(size: 14, weight: .bold))

            Text(String(localized: "onboarding.goals.subtitle"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)

            // Added goals
            VStack(spacing: 4) {
                ForEach(goalInputs.indices, id: \.self) { i in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.purple)
                            .frame(width: 6, height: 6)
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
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.purple.opacity(0.06)))
                }
            }

            // Input
            if goalInputs.count < 3 {
                VStack(spacing: 6) {
                    TextField(String(localized: "onboarding.goals.placeholder"), text: $newGoalTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))

                    HStack {
                        Text(String(localized: "onboarding.goals.target.date"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        DatePicker("", selection: $newGoalDate, displayedComponents: .date)
                            .labelsHidden()
                            .controlSize(.small)
                        Spacer()
                        Button {
                            if !newGoalTitle.isEmpty {
                                goalInputs.append((newGoalTitle, newGoalDate))
                                newGoalTitle = ""
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .bold))
                                Text(String(localized: "common.add"))
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 5).fill(
                                newGoalTitle.isEmpty ? Color.gray : Color.purple))
                        }
                        .buttonStyle(.plain)
                        .disabled(newGoalTitle.isEmpty)
                    }
                }
            }

            // Presets (only when empty)
            if goalInputs.isEmpty {
                VStack(spacing: 4) {
                    Text(String(localized: "onboarding.goals.quick.select"))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 6) {
                        presetChip(String(localized: "onboarding.goals.preset.certification"))
                        presetChip(String(localized: "onboarding.goals.preset.sideproject"))
                        presetChip(String(localized: "onboarding.goals.preset.health"))
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
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
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 1: Schedule

    private var scheduleStep: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 28))
                .foregroundStyle(.purple)

            Text(String(localized: "onboarding.schedule.title"))
                .font(.system(size: 14, weight: .bold))

            Text(String(localized: "onboarding.schedule.subtitle"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            VStack(spacing: 10) {
                scheduleRow(String(localized: "onboarding.schedule.work.start"), value: $goalService.profile.workStartHour, range: 6...12)
                scheduleRow(String(localized: "onboarding.schedule.work.end"), value: $goalService.profile.workEndHour, range: 15...22)
                Divider()
                scheduleRow(String(localized: "onboarding.schedule.lunch"), value: $goalService.profile.lunchStartHour, range: 11...14)
                scheduleRow(String(localized: "onboarding.schedule.commute"), value: $goalService.profile.commuteMinutes, range: 0...120, unit: String(localized: "onboarding.schedule.unit.minute"), step: 10)
            }
        }
        .padding(.horizontal, 16)
    }

    private func scheduleRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, unit: String? = nil, step: Int = 1) -> some View {
        let displayUnit = unit ?? String(localized: "onboarding.schedule.unit.hour")
        return VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                Spacer()
                Text("\(value.wrappedValue)\(displayUnit)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.purple)
            }
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0) }
            ), in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step))
            .controlSize(.small)
        }
    }

    // MARK: - Step 2: Energy

    private var energyStep: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 28))
                .foregroundStyle(.purple)

            Text(String(localized: "onboarding.energy.title"))
                .font(.system(size: 14, weight: .bold))

            Text(String(localized: "onboarding.energy.subtitle"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)

            VStack(spacing: 6) {
                ForEach(EnergyType.allCases, id: \.self) { type in
                    energyOption(type)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func energyOption(_ type: EnergyType) -> some View {
        let selected = goalService.profile.energyType == type
        return Button {
            goalService.profile.energyType = type
        } label: {
            HStack(spacing: 8) {
                Image(systemName: type == .morning ? "sunrise.fill" : type == .evening ? "moon.stars.fill" : "equal.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? .purple : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(type.rawValue)
                        .font(.system(size: 11, weight: .medium))
                    Text(type == .morning ? String(localized: "onboarding.energy.morning.desc") : type == .evening ? String(localized: "onboarding.energy.evening.desc") : String(localized: "onboarding.energy.balanced.desc"))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.purple)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.purple.opacity(0.08) : Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? Color.purple.opacity(0.3) : Color.secondary.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 3: Capacity

    private var capacityStep: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.system(size: 28))
                .foregroundStyle(.purple)

            Text(String(localized: "onboarding.capacity.title"))
                .font(.system(size: 14, weight: .bold))

            Text(String(localized: "onboarding.capacity.subtitle"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)

            VStack(spacing: 10) {
                capacitySlider(String(localized: "onboarding.capacity.weekday"), value: $goalService.profile.weekdayCapacityMinutes)
                capacitySlider(String(localized: "onboarding.capacity.weekend"), value: $goalService.profile.weekendCapacityMinutes)
            }

            Divider()
                .padding(.vertical, 4)

            // Aggressiveness
            VStack(spacing: 6) {
                Text(String(localized: "onboarding.capacity.ai.level"))
                    .font(.system(size: 11, weight: .medium))

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
            }
        }
        .padding(.horizontal, 16)
    }

    private func capacitySlider(_ label: String, value: Binding<Int>) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                Spacer()
                Text(String(format: String(localized: "onboarding.capacity.minutes.format"), value.wrappedValue))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.purple)
            }
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0) }
            ), in: 30...300, step: 15)
            .controlSize(.small)
        }
    }

    private var aggressivenessDesc: String {
        switch goalService.profile.aggressiveness {
        case .manual: return String(localized: "aggressiveness.manual.desc")
        case .assist: return String(localized: "aggressiveness.assist.desc")
        case .semiAuto: return String(localized: "aggressiveness.semiauto.desc")
        case .auto: return String(localized: "aggressiveness.auto.desc")
        }
    }

    // MARK: - Complete

    private func completeOnboarding() {
        for (title, due) in goalInputs {
            let goal = Goal(level: .year, title: title, dueDate: due, weight: 4,
                           recurrence: RecurrencePlan(weeklyTargetSessions: 4, perSessionMinutes: 60,
                                                       allowedDays: [1, 2, 3, 4, 5]))
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
