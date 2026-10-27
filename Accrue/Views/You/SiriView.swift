import AppIntents
import SwiftUI

/// What to say to Siri, and a link to every Accrue action in the Shortcuts app.
struct SiriView: View {
    @Environment(\.palette) private var palette

    private static let groups: [(title: String, phrases: [String])] = [
        ("Your plan and progress", [
            "What's my workout today in Accrue?",
            "How's my bench press in Accrue?",
            "How's my week in Accrue?",
        ]),
        ("During a workout", [
            "Start my workout in Accrue",
            "Log a set in Accrue … bench 155 for 5",
            "What's next in Accrue?",
            "Undo my last set in Accrue",
            "Pause my Accrue workout",
            "End my Accrue workout",
        ]),
    ]

    var body: some View {
        Form {
            ForEach(Self.groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.phrases, id: \.self) { phrase in
                        Label {
                            Text("“\(phrase)”").foregroundStyle(palette.text)
                        } icon: {
                            Image(systemName: "waveform").foregroundStyle(palette.accentText)
                        }
                    }
                }
                .listRowBackground(palette.card)
            }
            Section {
                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } footer: {
                Text("Shortcuts has every action: plans for any day, your log, personal bests, adding, swapping and removing exercises, your weekly routine, favorites, settings and how-tos. Run any of them with Siri by its name, or put them together in your own shortcuts.")
                    .font(.inter(13))
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("Siri & Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
    }
}
