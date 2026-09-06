import SwiftUI

struct PaceStatusView: View {
    let status: PaceStatus
    let message: String
    let color: Color

    private var symbol: String {
        switch status {
        case .slowDown: "gauge.with.dots.needle.67percent"
        case .onTrack: "checkmark"
        case .roomToUseMore: "arrow.up.right"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color)
                Text(StatusText.title(status))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
