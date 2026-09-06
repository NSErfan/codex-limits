import SwiftUI

/// A stable, readable detail strip shared by the window and history charts.
struct ChartHoverReadout: View {
    let title: String
    let detail: String
    var symbol: String? = nil
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize()
            }
            if let hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .monospacedDigit()
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        }
    }
}
