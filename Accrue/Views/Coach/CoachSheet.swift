import AccrueKit
import SwiftUI

/// The Coach sheet that the round lime button opens (ACoach boards): half height over Train,
/// full screen with the expand button, the conversation, quick chips, + for photos and files,
/// and a field with a hold-to-talk mic.
struct CoachSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var detent = UserDefaults.standard.string(forKey: "progressScreen") == "coachfull"
        ? PresentationDetent.large : CoachSheet.half
    @State private var draft = ""
    @State private var speech = SpeechInput()
    @FocusState private var typing: Bool

    static let half = PresentationDetent.height(470)

    private var full: Bool { detent == .large }

    var body: some View {
        let coach = model.coach
        VStack(spacing: 0) {
            header
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(full ? coach.messages : Array(coach.messages.suffix(2))) { message in
                            bubble(message).id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: coach.messages.count) {
                    if let last = coach.messages.last { withAnimation { scroller.scrollTo(last.id, anchor: .bottom) } }
                }
                .overlay {
                    if coach.messages.isEmpty { emptyState }
                }
            }
            composer
        }
        .foregroundStyle(palette.text)
        .background(palette.card)
        .presentationDetents([Self.half, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(26)
        .presentationBackground(palette.card)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Coach")
                .font(.display(full ? 28 : 24))
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
            roundButton(full ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                        label: full ? "Shrink to half" : "Expand to full screen") {
                withAnimation { detent = full ? Self.half : .large }
            }
            roundButton("chevron.down", label: "Collapse coach") { dismiss() }
        }
        .padding(.horizontal, 16)
        .padding(.top, full ? 18 : 14)
        .padding(.bottom, 12)
    }

    private func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 40, height: 40)
                .background(palette.raised, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Conversation

    private func bubble(_ message: CoachModel.Message) -> some View {
        let mine = message.from == .me
        return VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
            Text(message.text)
                .font(.inter(15))
                .lineSpacing(3)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(mine ? palette.line.opacity(0.75) : palette.raised,
                            in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: mine ? 20 : 4,
                                                       bottomTrailingRadius: mine ? 4 : 20, topTrailingRadius: 20))
            if !message.logged.isEmpty {
                Button("Undo") { model.coach.undo(message) }
                    .font(.inter(13, .semibold))
                    .foregroundStyle(palette.accentText)
                    .padding(.leading, 6)
            }
        }
        .frame(maxWidth: 300, alignment: mine ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private var emptyState: some View {
        Text("Tell me what you did, like \"pulls 100, six by ten\", and I'll log it.")
            .font(.inter(15))
            .foregroundStyle(palette.secondary)
            .multilineTextAlignment(.center)
            .padding(32)
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 10) {
            if !full {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("Log what I just did") { draft = currentExerciseName.map { "\($0) " } ?? ""; typing = true }
                        chip("Swap this lift") { send("Swap \(currentExerciseName ?? "this lift") for something else") }
                        chip("Plan next week") { send("Plan next week") }
                    }
                }
            }
            HStack(spacing: 8) {
                Menu {
                    Button("Take photo", systemImage: "camera") {}
                    Button("Photos", systemImage: "photo.on.rectangle") {}
                    Button("File", systemImage: "doc") {}
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(palette.raised, in: Circle())
                }
                .accessibilityLabel("Add a photo or file")
                TextField("Type, or hold the mic", text: speech.listening ? .constant(speech.text) : $draft)
                    .font(.inter(15))
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit { send(draft) }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(palette.raised, in: Capsule())
                mic
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.inter(13, .semibold))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .overlay(Capsule().strokeBorder(palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Hold to talk; let go to send what was heard. With text typed, it sends that instead.
    private var mic: some View {
        let hasDraft = !draft.trimmingCharacters(in: .whitespaces).isEmpty && !speech.listening
        return Image(systemName: hasDraft ? "arrow.up" : "mic.fill")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(palette.onAccent)
            .frame(width: 56, height: 56)
            .background(palette.accentFill, in: Circle())
            .scaleEffect(speech.listening ? 1.12 : 1)
            .animation(.spring(duration: 0.25), value: speech.listening)
            .onTapGesture { if hasDraft { send(draft) } }
            .onLongPressGesture(minimumDuration: 0.15, maximumDistance: 80) {
            } onPressingChanged: { pressing in
                guard !hasDraft else { return }
                if pressing {
                    speech.start()
                } else if speech.listening {
                    send(speech.stop())
                }
            }
            .accessibilityLabel(hasDraft ? "Send" : "Hold to talk")
            .accessibilityAddTraits(.isButton)
    }

    private func send(_ text: String) {
        model.coach.send(text)
        draft = ""
    }

    /// The exercise on the Train card that is recording, for the chips.
    private var currentExerciseName: String? {
        guard let session = model.data.activeSession, let partID = session.partID,
              let part = model.data.parts(on: session.day).first(where: { $0.id == partID }) else { return nil }
        let items = model.data.items(in: part)
        let next = items.first { item in
            model.data.sets(of: item.exerciseID, on: session.day, partID: partID).filter { !$0.isWarmup }.count < item.sets
        } ?? items.last
        return next.map { model.name(of: $0.exerciseID).lowercased() }
    }
}
