import SwiftUI

enum AppTab: String, Hashable {
    case train, plans, progress, you
}

/// Four tabs: Train, Plans, Progress, You. Siri and Shortcuts can switch tabs and open a how-to.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SettingsKey.appearance) private var appearance = Appearance.dark
    /// `-startTab plans` opens another tab first (used for screenshots).
    @State private var tab = AppTab(rawValue: UserDefaults.standard.string(forKey: "startTab") ?? "") ?? .train
    @State private var howTo: HowToLink?

    private struct HowToLink: Identifiable { var id: String }

    var body: some View {
        let palette: Palette = colorScheme == .dark ? .limeNight : .sageAndLime
        Group {
            if model.catalogLoaded {
                // The system tab bar is hidden; each tab gets the custom bar as a bottom inset,
                // because an inset on the TabView itself does not reach the tabs' content.
                TabView(selection: $tab) {
                    withTabBar(TrainView()).tag(AppTab.train)
                    withTabBar(PlansView()).tag(AppTab.plans)
                    withTabBar(ProgressScreen()).tag(AppTab.progress)
                    withTabBar(YouView()).tag(AppTab.you)
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
        .fullScreenCover(item: $howTo) { link in
            HowToView(exerciseID: link.id)
        }
        .onChange(of: model.route, initial: true) { _, route in
            switch route {
            case .tab(let value)?: tab = value
            case .howTo(let id)?: howTo = HowToLink(id: id)
            case nil: return
            }
            model.route = nil
        }
        .environment(\.palette, palette)
        .tint(palette.accentText)
        .preferredColorScheme(appearance.colorScheme)
    }

    private func withTabBar(_ content: some View) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AccrueTabBar(tab: $tab)
            }
    }
}

struct AccrueTabBar: View {
    @Environment(\.palette) private var palette
    @Binding var tab: AppTab

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            item(.train, "Train", "dumbbell")
            item(.plans, "Plans", "rectangle.split.2x1")
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
