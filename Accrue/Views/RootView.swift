import SwiftUI

enum AppTab: String, Hashable {
    case train, plans, progress, you
}

/// Five-slot tab bar: Train, Plans, the round lime Coach button, Progress, You.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SettingsKey.appearance) private var appearance = Appearance.dark
    /// `-startTab plans` opens another tab first (used for screenshots).
    @State private var tab = AppTab(rawValue: UserDefaults.standard.string(forKey: "startTab") ?? "") ?? .train
    @State private var coachOpen = false

    var body: some View {
        let palette: Palette = colorScheme == .dark ? .limeNight : .sageAndLime
        Group {
            if model.catalogLoaded {
                TabView(selection: $tab) {
                    TrainView().tag(AppTab.train).toolbar(.hidden, for: .tabBar)
                    PlansView().tag(AppTab.plans).toolbar(.hidden, for: .tabBar)
                    ProgressScreen().tag(AppTab.progress).toolbar(.hidden, for: .tabBar)
                    YouView().tag(AppTab.you).toolbar(.hidden, for: .tabBar)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    AccrueTabBar(tab: $tab, coachOpen: $coachOpen)
                }
            } else {
                ZStack {
                    palette.background.ignoresSafeArea()
                    Text("ACCRUE")
                        .font(.display(44))
                        .foregroundStyle(palette.accentText)
                }
            }
        }
        .sheet(isPresented: $coachOpen) {
            CoachSheet()
                .presentationDetents([.fraction(0.12), .medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .environment(\.palette, palette)
        .tint(palette.accentText)
        .preferredColorScheme(appearance.colorScheme)
    }
}

struct AccrueTabBar: View {
    @Environment(\.palette) private var palette
    @Binding var tab: AppTab
    @Binding var coachOpen: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            item(.train, "Train", "dumbbell")
            item(.plans, "Plans", "rectangle.split.2x1")
            Button {
                coachOpen = true
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(palette.onAccent)
                    .frame(width: 50, height: 50)
                    .background(palette.accentFill, in: Circle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Coach")
            item(.progress, "Progress", "chart.line.uptrend.xyaxis")
            item(.you, "You", "person")
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .background(alignment: .top) {
            palette.background
                .overlay(alignment: .top) { Rectangle().fill(palette.line.opacity(0.5)).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func item(_ value: AppTab, _ title: String, _ icon: String) -> some View {
        Button {
            tab = value
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                Text(title).font(.inter(11, .semibold, relativeTo: .caption2))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(tab == value ? palette.accentText : palette.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == value ? .isSelected : [])
    }
}
