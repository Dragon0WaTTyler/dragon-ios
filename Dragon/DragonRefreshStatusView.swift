import Foundation
import SwiftUI

struct DragonRefreshStatusView: View {
    let lastUpdatedAt: Date?
    let isRefreshing: Bool
    let errorText: String?
    let statusText: String?

    init(
        lastUpdatedAt: Date?,
        isRefreshing: Bool,
        errorText: String?,
        statusText: String? = nil
    ) {
        self.lastUpdatedAt = lastUpdatedAt
        self.isRefreshing = isRefreshing
        self.errorText = errorText
        self.statusText = statusText
    }

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

            if let statusText, !statusText.isEmpty {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            if let errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(DragonTheme.red)
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
