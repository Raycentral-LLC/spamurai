#if DEBUG
import SwiftUI
import WidgetKit

/// Debug only (launch with -widgets): renders every widget size with sample data for screenshots.
struct WidgetGallery: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                tile(.systemSmall, width: 170, height: 170)
                tile(.systemMedium, width: 364, height: 170)
                tile(.systemLarge, width: 364, height: 382)
                HStack(spacing: 14) {
                    lock(.accessoryCircular, width: 72, height: 72)
                    lock(.accessoryRectangular, width: 172, height: 76)
                }
            }
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity)
        }
        .background(Color(white: 0.12))
    }

    private func tile(_ family: WidgetFamily, width: CGFloat, height: CGFloat) -> some View {
        SpamuraiWidgetView(entry: .placeholder, family: family)
            .padding(16)
            .frame(width: width, height: height)
            .background(WidgetBackground())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func lock(_ family: WidgetFamily, width: CGFloat, height: CGFloat) -> some View {
        SpamuraiWidgetView(entry: .placeholder, family: family)
            .frame(width: width, height: height)
            .foregroundStyle(.white)
            .padding(6)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}
#endif
