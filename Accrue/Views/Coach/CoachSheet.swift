import SwiftUI

/// The Coach sheet that the round lime button opens. The coach itself (on-device model that
/// logs workouts and writes plans) is a later step; this holds its place in the layout.
struct CoachSheet: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.onAccent)
                    .frame(width: 36, height: 36)
                    .background(palette.accentFill, in: Circle())
                Text("Coach")
                    .font(.display(28))
                    .textCase(.uppercase)
            }
            Text("Soon you can tell the coach what you did (\"3 sets of pull-ups, 8 each\") and it logs it, or ask it to write or tune a preset. It runs on your iPhone.")
                .font(.inter(15))
                .foregroundStyle(palette.secondary)
            Spacer()
        }
        .padding(20)
        .foregroundStyle(palette.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.background)
    }
}
