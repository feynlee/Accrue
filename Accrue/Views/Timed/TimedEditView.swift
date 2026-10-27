import AccrueKit
import SwiftUI

/// Build or change a timed exercise, to the MCircuitEdit board: start from a template, set work,
/// rest and rounds, then swap, add, remove or drag the moves. Changes save as you make them.
struct TimedEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let timedID: UUID
    /// A move whose swap choices start open.
    var startOpen: Int? = nil
    @State private var open: Int?
    @State private var adding = false
    @State private var confirmingDelete = false

    var body: some View {
        if let plan = model.data.timedExercise(timedID) {
            content(plan)
        } else {
            Text("This timed exercise was removed.")
                .foregroundStyle(palette.secondary)
        }
    }

    private func content(_ plan: TimedExercise) -> some View {
        List {
            Section {
                header(plan)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                ForEach(Array(plan.moves.enumerated()), id: \.offset) { i, move in
                    row(plan, index: i, move: move)
                        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove { from, to in edit { $0.moves.move(fromOffsets: from, toOffset: to) } }
            } header: {
                HStack {
                    Text("\(plan.moves.count) exercises")
                    Spacer()
                    Text("Swap keeps the body area").textCase(nil).tracking(0).font(.inter(11, .semibold))
                }
                .sectionLabel()
                .padding(.horizontal, 4)
            }
            Section {
                footer
                    .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 16, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .onAppear { if open == nil { open = startOpen } }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .scrollContentBackground(.hidden)
        .background(palette.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.fontWeight(.bold)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Delete timed exercise", role: .destructive) { confirmingDelete = true }
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack {
                ExercisePicker(title: "Add a move") { id in
                    edit { $0.moves.append(id) }
                    adding = false
                }
            }
        }
        .confirmationDialog("Delete \(plan.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.update { $0.deleteTimed(timedID) }
                dismiss()
            }
        } message: {
            Text("It also comes off every day it is on. Workouts you did stay in your history.")
        }
    }

    private func edit(_ change: (inout TimedExercise) -> Void) {
        guard var plan = model.data.timedExercise(timedID) else { return }
        change(&plan)
        model.update { $0.upsert(plan) }
    }

    // MARK: Top

    private func header(_ plan: TimedExercise) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("Name", text: Binding(get: { plan.name }, set: { name in edit { $0.name = name } }))
                    .font(.display(36))
                    .textCase(.uppercase)
                    .foregroundStyle(palette.text)
                Text("TIMED")
                    .font(.inter(11, .heavy))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .foregroundStyle(palette.accentText)
                    .background(palette.accentSoft, in: Capsule())
            }
            .padding(.horizontal, 4)
            Text("A timed exercise is built from other exercises in the library. It sits in the library like any exercise, so you can add it to a day. Good for HIIT, 7-minute or Tabata.")
                .font(.inter(12))
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 4)
            Text("Start from").sectionLabel().padding(.horizontal, 4)
            HStack(spacing: 6) {
                ForEach(TimedStyle.allCases, id: \.self) { style in
                    let on = style == plan.style
                    Button {
                        edit { current in
                            var next = TimedExercise.template(style)
                            next.id = current.id
                            current = next
                        }
                        open = nil
                    } label: {
                        VStack(spacing: 2) {
                            Text(style.label).font(.inter(13, .heavy)).foregroundStyle(palette.text)
                            Text(style.detail).font(.inter(10)).foregroundStyle(palette.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(on ? palette.raised : palette.sunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(on ? palette.accentText : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            HStack(spacing: 6) {
                timing("WORK", "\(plan.workSeconds) s", palette.accentText, less: "Less work time", more: "More work time",
                       down: { edit { $0.workSeconds = max(10, $0.workSeconds - 5) } },
                       up: { edit { $0.workSeconds = min(120, $0.workSeconds + 5) } })
                timing("REST", "\(plan.restSeconds) s", palette.cardio, less: "Less rest", more: "More rest",
                       down: { edit { $0.restSeconds = max(0, $0.restSeconds - 5) } },
                       up: { edit { $0.restSeconds = min(120, $0.restSeconds + 5) } })
                timing("ROUNDS", "× \(plan.rounds)", palette.secondary, less: "Fewer rounds", more: "More rounds",
                       down: { edit { $0.rounds = max(1, $0.rounds - 1) } },
                       up: { edit { $0.rounds = min(10, $0.rounds + 1) } })
            }
            .padding(8)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack {
                Text("\(plan.moves.count) exercises × \(plan.rounds)" + (plan.rounds > 1
                     ? " rounds · \(DurationFormat.clock(TimeInterval(plan.roundRestSeconds))) between rounds" : " round"))
                    .font(.inter(12))
                    .foregroundStyle(palette.secondary)
                Spacer()
                Text(DurationFormat.clock(TimeInterval(plan.totalSeconds())))
                    .font(.number(22))
                    .foregroundStyle(palette.accentText)
            }
            .padding(.horizontal, 4)
            Text(plan.style.note)
                .font(.inter(12))
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func timing(_ key: String, _ value: String, _ color: Color, less: String, more: String,
                        down: @escaping () -> Void, up: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Text(key).font(.inter(11, .bold)).tracking(0.4).foregroundStyle(color)
            HStack {
                circleButton("minus", less, down)
                Spacer(minLength: 0)
                Text(value).font(.number(26)).monospacedDigit().foregroundStyle(palette.text).lineLimit(1).fixedSize()
                Spacer(minLength: 0)
                circleButton("plus", more, up)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func circleButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 32, height: 32)
                .foregroundStyle(palette.text)
                .background(palette.raised, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Moves

    private func row(_ plan: TimedExercise, index i: Int, move: String) -> some View {
        let area = model.catalog.timedArea(of: move)
        let isOpen = open == i
        let swaps = (TimedMoves.byArea[area] ?? []).filter { !plan.moves.contains($0) }.prefix(4)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.line)
                    .accessibilityLabel("Drag to reorder")
                Text("\(i + 1)")
                    .font(.inter(11, .heavy))
                    .foregroundStyle(palette.secondary.opacity(0.8))
                    .frame(width: 18, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name(of: move))
                        .font(.inter(14, .bold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(area.color).frame(width: 7, height: 7)
                        Text(area.label)
                    }
                    .font(.inter(11))
                    .foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 4)
                Button {
                    withAnimation(.snappy) { open = isOpen ? nil : i }
                } label: {
                    Label("Swap", systemImage: "arrow.left.arrow.right")
                        .font(.inter(12, .heavy))
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .foregroundStyle(isOpen ? palette.onAccent : palette.text)
                        .background(isOpen ? palette.accentFill : palette.raised, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Swap \(model.name(of: move)) for another \(area.label.lowercased()) exercise")
                Button {
                    open = nil
                    edit { $0.moves.remove(at: i) }
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(palette.danger)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(model.name(of: move))")
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .frame(minHeight: 48)
            if isOpen {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Other \(area.label.lowercased()) moves, no equipment")
                        .font(.inter(11))
                        .foregroundStyle(palette.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(Array(swaps), id: \.self) { pick in
                            Button {
                                edit { $0.moves[i] = pick }
                                withAnimation(.snappy) { open = nil }
                            } label: {
                                Text(model.name(of: pick))
                                    .font(.inter(12, .bold))
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .foregroundStyle(palette.accentText)
                                    .overlay(Capsule().strokeBorder(palette.accentText, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            adding = true
                        } label: {
                            Text("Library…")
                                .font(.inter(12, .bold))
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .foregroundStyle(palette.text)
                                .background(palette.raised, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 50)
                .padding(.trailing, 10)
                .padding(.bottom, 10)
            }
        }
        .background(isOpen ? palette.raised.opacity(0.6) : palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Button {
                adding = true
            } label: {
                Text("+ Add from library")
                    .font(.inter(14, .bold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(palette.text)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(palette.line, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            }
            .buttonStyle(.plain)
            Button("Shuffle within areas") { shuffle() }
                .buttonStyle(FooterButtonStyle())
        }
    }

    /// Each move becomes another one from its area, so the balance stays the same.
    private func shuffle() {
        open = nil
        edit { plan in
            var used = Set<String>()
            plan.moves = plan.moves.map { move in
                let area = model.catalog.timedArea(of: move)
                let options = (TimedMoves.byArea[area] ?? []).filter { !used.contains($0) && $0 != move }
                let pick = options.randomElement() ?? move
                used.insert(pick)
                return pick
            }
        }
    }
}

private struct FooterButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(13, .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(palette.text)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
