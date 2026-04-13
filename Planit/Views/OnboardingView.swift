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
                Text("Calen 설정")
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
                        Text("이전")
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
                    Text(step == 3 ? "시작하기" : "다음")
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

            Text("올해 목표를 알려주세요")
                .font(.system(size: 14, weight: .bold))

            Text("1~3개의 핵심 목표를 설정하면\nAI가 매일 일정을 자동으로 잡아줍니다")
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
                    TextField("목표 (예: 정보처리기사 합격)", text: $newGoalTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))

                    HStack {
                        Text("목표일")
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
                                Text("추가")
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
                    Text("빠른 선택")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 6) {
                        presetChip("자격증 합격")
                        presetChip("사이드 프로젝트")
                        presetChip("건강/운동")
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

            Text("생활 패턴을 알려주세요")
                .font(.system(size: 14, weight: .bold))

            Text("일정 배치에 활용됩니다")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            VStack(spacing: 10) {
                scheduleRow("출근", value: $goalService.profile.workStartHour, range: 6...12)
                scheduleRow("퇴근", value: $goalService.profile.workEndHour, range: 15...22)
                Divider()
                scheduleRow("점심", value: $goalService.profile.lunchStartHour, range: 11...14)
                scheduleRow("통근", value: $goalService.profile.commuteMinutes, range: 0...120, unit: "분", step: 10)
            }
        }
        .padding(.horizontal, 16)
    }

    private func scheduleRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, unit: String = "시", step: Int = 1) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                Spacer()
                Text("\(value.wrappedValue)\(unit)")
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

            Text("에너지 타입은?")
                .font(.system(size: 14, weight: .bold))

            Text("집중력이 높은 시간대에\n중요한 일정을 배치합니다")
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
                    Text(type == .morning ? "오전에 집중력 최고" : type == .evening ? "오후/저녁에 집중력 최고" : "시간대 상관없이 고른 편")
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

            Text("하루 집중 가능 시간")
                .font(.system(size: 14, weight: .bold))

            Text("목표를 위해 하루에\n쓸 수 있는 시간을 설정하세요")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)

            VStack(spacing: 10) {
                capacitySlider("평일", value: $goalService.profile.weekdayCapacityMinutes)
                capacitySlider("주말", value: $goalService.profile.weekendCapacityMinutes)
            }

            Divider()
                .padding(.vertical, 4)

            // Aggressiveness
            VStack(spacing: 6) {
                Text("AI 자동 배치 수준")
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
                Text("\(value.wrappedValue)분")
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
        case .manual: return "제안만 보여줌, 자동 추가 안함"
        case .assist: return "30분 이하 블록만 자동 추가"
        case .semiAuto: return "상위 1-2개 자동, 나머지 제안"
        case .auto: return "모두 자동 추가, 충돌 시만 확인"
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
