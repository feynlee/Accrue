import AccrueKit
import SwiftUI

/// The full-screen how-to, as on the AHowTo board: the figure on a light panel playing the
/// current step, then the step's text, breathing, working muscles and cues, with Back / Next.
struct HowToView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let exerciseID: String
    /// What the last button says: "Back to the set" from Train, "Done" from Plans.
    var doneLabel = "Done"
    @State private var index: Int
    @State private var playing = true
    @State private var speedIndex = 0
    @State private var faultIndex = 0
    @State private var glass = false

    private static let speeds: [(Double, String)] = [(1, "1×"), (0.5, "0.5×"), (0.25, "0.25×")]
    private static let panelInk = Color(hex: 0x0E0F12)
    private static let panelSecondary = Color(hex: 0x4A4F58)

    init(exerciseID: String, doneLabel: String = "Done", startStep: Int = 0, glass: Bool = false) {
        self.exerciseID = exerciseID
        self.doneLabel = doneLabel
        _index = State(initialValue: startStep)
        _glass = State(initialValue: glass)
    }

    var body: some View {
        if let exercise = model.exercise(exerciseID), let guide = model.catalog.howTo(for: exercise), !guide.steps.isEmpty {
            let i = min(index, guide.steps.count - 1)
            let step = guide.steps[i]
            VStack(spacing: 0) {
                panel(guide, step: step, i: i)
                ScrollView {
                    content(guide, step: step, i: i)
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                bottomBar(guide, i: i)
            }
            .background(palette.background.ignoresSafeArea())
            .onChange(of: index) { faultIndex = 0 }
        } else {
            VStack(spacing: 12) {
                Text("No how-to for this exercise yet.")
                    .font(.inter(15))
                    .foregroundStyle(palette.secondary)
                Button("Close") { dismiss() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.background.ignoresSafeArea())
        }
    }

    // MARK: Demo panel

    private func panel(_ guide: HowToGuide, step: HowToStep, i: Int) -> some View {
        let fault = step.kind == .mistakes ? step.mistakes.filter { $0.pose != nil }[safe: faultIndex] : nil
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: 0xF2F3F5))
                        .frame(width: 40, height: 40)
                        .background(Self.panelInk, in: Circle())
                }
                .accessibilityLabel("Close")
                VStack(spacing: 0) {
                    Text(guide.name)
                        .font(.inter(15, .heavy))
                        .foregroundStyle(Self.panelInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("Step \(i + 1) of \(guide.steps.count)")
                        .font(.inter(12, .semibold))
                        .foregroundStyle(Self.panelSecondary)
                }
                .frame(maxWidth: .infinity)
                Button {
                    speedIndex = (speedIndex + 1) % Self.speeds.count
                } label: {
                    Text(Self.speeds[speedIndex].1)
                        .font(.inter(13, .heavy))
                        .foregroundStyle(Color(hex: 0xF2F3F5))
                        .frame(width: 52, height: 40)
                        .background(Self.panelInk, in: Capsule())
                }
                .accessibilityLabel("Speed \(Self.speeds[speedIndex].1)")
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            ExerciseDemo(guide: guide, window: step.window, speed: Self.speeds[speedIndex].0,
                         playing: playing, fault: fault, interactive: true, glass: glass)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) {
                    if guide.bodyModel == "anatomy" {
                        Button {
                            glass.toggle()
                        } label: {
                            Text(glass ? "Muscles" : "Glass")
                                .font(.inter(12, .heavy))
                                .foregroundStyle(Self.panelInk)
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(Color.white.opacity(0.7), in: Capsule())
                                .overlay(Capsule().stroke(Self.panelInk.opacity(0.15)))
                        }
                        .accessibilityLabel(glass ? "Show the muscles" : "See the bones through the muscles")
                        .padding(12)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let fault {
                        Text(fault.name)
                            .font(.inter(11, .heavy))
                            .foregroundStyle(FigureInk.fault)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Self.panelInk, in: RoundedRectangle(cornerRadius: 8))
                            .padding(12)
                    }
                }

            HStack(spacing: 8) {
                Button {
                    playing.toggle()
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: 0xF2F3F5))
                        .frame(width: 36, height: 36)
                        .background(Self.panelInk, in: Circle())
                }
                .accessibilityLabel(playing ? "Pause the demo" : "Play the demo")
                HStack(spacing: 3) {
                    ForEach(guide.steps) { s in
                        Button {
                            index = s.id
                        } label: {
                            Capsule()
                                .fill(s.id == i ? Self.panelInk : s.id < i ? Color(hex: 0x6B7180) : Color(hex: 0xC9CDD4))
                                .frame(height: 5)
                                .frame(maxWidth: .infinity, minHeight: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Step \(s.id + 1): \(s.title)")
                    }
                }
                Text(step.window.lowerBound == step.window.upperBound ? "Hold" : playing ? "Looping step \(i + 1)" : "Paused")
                    .font(.inter(11, .bold))
                    .foregroundStyle(Self.panelSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(height: 392)
        .background(palette.demo.ignoresSafeArea(edges: .top))
    }

    // MARK: Step text

    @ViewBuilder
    private func content(_ guide: HowToGuide, step: HowToStep, i: Int) -> some View {
        let bad = step.kind == .mistakes
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("STEP \(i + 1) · \(step.kicker)")
                    .font(.inter(11, .heavy))
                    .tracking(0.6)
                    .foregroundStyle(bad ? palette.danger : palette.accentText)
                Text(step.title)
                    .font(.display(28))
                    .textCase(.uppercase)
                    .foregroundStyle(palette.text)
                Text(step.body)
                    .font(.inter(14))
                    .lineSpacing(3)
                    .foregroundStyle(palette.text.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let breath = step.breath {
                HStack(spacing: 10) {
                    Image(systemName: "wind")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.cardio)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("BREATHE").font(.inter(11, .heavy)).tracking(0.5).foregroundStyle(palette.cardio)
                        Text(breath).font(.inter(14, .semibold)).foregroundStyle(palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(palette.cardio.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if guide.bodyModel == "anatomy", !guide.muscles.primary.isEmpty {
                musclesBox(guide.muscles)
            }

            if bad {
                mistakes(step.mistakes)
            } else if !step.cues.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("FORM CUES").font(.inter(11, .heavy)).tracking(0.5).foregroundStyle(palette.secondary)
                    ForEach(step.cues, id: \.self) { cue in
                        mark("checkmark", palette.accentFill, bold: cue.cue, rest: cue.why)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func musclesBox(_ muscles: MuscleSet) -> some View {
        HStack(alignment: .top, spacing: 12) {
            MuscleMap(muscles: muscles)
                .frame(width: 84, height: 136)
            VStack(alignment: .leading, spacing: 6) {
                Text("MUSCLES DOING THE WORK").font(.inter(11, .heavy)).tracking(0.5).foregroundStyle(palette.secondary)
                ForEach(muscles.primary.prefix(4), id: \.self) { muscleRow($0, role: "main", color: Color(hex: 0xC6F432)) }
                ForEach(muscles.secondary.prefix(4), id: \.self) { muscleRow($0, role: "helps", color: Color(hex: 0x6E8A1E)) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func muscleRow(_ id: String, role: String, color: Color) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(model.catalog.muscleLabel(id)).font(.inter(13, .bold)).foregroundStyle(palette.text)
            Text(role).font(.inter(13)).foregroundStyle(palette.secondary)
        }
    }

    /// Each mistake; tapping one with a pose shows it on the figure.
    private func mistakes(_ list: [Mistake]) -> some View {
        let shown = list.filter { $0.pose != nil }
        return VStack(alignment: .leading, spacing: 8) {
            Text("AVOID").font(.inter(11, .heavy)).tracking(0.5).foregroundStyle(palette.secondary)
            ForEach(list) { m in
                let n = shown.firstIndex(of: m)
                Button {
                    if let n { faultIndex = n }
                } label: {
                    mark("xmark", palette.danger, bold: m.name + ".", rest: "\(m.looks) Fix: \(m.fix)")
                        .padding(8)
                        .background(n != nil && n == faultIndex ? palette.card : .clear,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(n == nil)
            }
            if !shown.isEmpty {
                Text("Tap a mistake to see it in red over the right form.")
                    .font(.inter(12))
                    .foregroundStyle(palette.secondary)
            }
        }
    }

    private func mark(_ symbol: String, _ color: Color, bold: String, rest: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(palette.onAccent)
                .frame(width: 18, height: 18)
                .background(color, in: Circle())
                .padding(.top, 1)
            (Text(bold).font(.inter(14, .bold)).foregroundColor(palette.text)
             + Text(" " + rest).font(.inter(14)).foregroundColor(palette.secondary))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Back / Next

    private func bottomBar(_ guide: HowToGuide, i: Int) -> some View {
        let last = i == guide.steps.count - 1
        return HStack(spacing: 8) {
            Button {
                index = max(0, i - 1)
            } label: {
                Text("‹ Back")
                    .font(.inter(15, .heavy))
                    .frame(width: 110, height: 52)
                    .foregroundStyle(i > 0 ? palette.text : palette.secondary.opacity(0.6))
                    .background(palette.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(i == 0)
            Button {
                if last { dismiss() } else { index = i + 1 }
            } label: {
                Text(last ? doneLabel : "Next: \(guide.steps[i + 1].title) ›")
                    .font(.inter(16, .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(palette.onAccent)
                    .background(palette.accentFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .overlay(alignment: .top) { Rectangle().fill(palette.raised).frame(height: 1) }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
