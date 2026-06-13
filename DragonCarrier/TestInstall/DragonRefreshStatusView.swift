import Foundation
import SwiftUI

struct DragonRefreshStatusView: View {
    let lastUpdatedAt: Date?
    let isRefreshing: Bool
    let errorText: String?
    let statusText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(lastUpdatedLabel)
                    .font(.caption)
                    .foregroundStyle(.gray)

                if isRefreshing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(DragonTheme.red)
                }
            }

            if let errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(DragonTheme.red)
            }

            if let statusText, !statusText.isEmpty {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
    }

    private var lastUpdatedLabel: String {
        guard let lastUpdatedAt else {
            return "Last updated: Never"
        }

        return "Last updated: \(Self.formatter.string(from: lastUpdatedAt))"
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}
