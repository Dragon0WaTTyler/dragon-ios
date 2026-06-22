import SwiftUI

struct DragonTVAdminDiagnosticsView: View {
    let diagnostics: [IPTVSourceDiagnostic]
    let lastUpdatedAt: Date?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DragonTheme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if diagnostics.isEmpty {
                        DragonAdminSectionCard(
                            title: "TV Diagnostics",
                            status: "Unavailable",
                            statusColor: .gray,
                            message: "No cached TV diagnostics are available yet."
                        ) {
                            EmptyView()
                        }
                    } else {
                        ForEach(diagnostics) { diagnostic in
                            DragonAdminSectionCard(
                                title: diagnostic.label,
                                status: diagnosticStatusText(for: diagnostic),
                                statusColor: diagnosticStatusColor(for: diagnostic),
                                message: diagnostic.url.absoluteString
                            ) {
                                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 10) {
                                    DragonAdminMetricView(
                                        label: "Parsed",
                                        value: "\(diagnostic.parsedChannelCount)"
                                    )
                                    DragonAdminMetricView(
                                        label: "Working",
                                        value: diagnostic.validChannelCount.map(String.init) ?? "Not checked yet"
                                    )
                                    DragonAdminMetricView(
                                        label: "Sports/beIN",
                                        value: "\(diagnostic.interestingMatchCount)"
                                    )
                                }

                                if let errorMessage = diagnostic.errorMessage?.dragonTrimmedOrNil {
                                    Text(errorMessage)
                                        .font(.caption)
                                        .foregroundStyle(DragonTheme.red)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(DragonTheme.card)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text("TV Diagnostics")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)

                Text(lastUpdatedLabel)
                    .font(.footnote)
                    .foregroundStyle(.gray)
            }

            Spacer()
        }
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    private var lastUpdatedLabel: String {
        guard let lastUpdatedAt else {
            return "Last refresh unavailable"
        }

        return "Last refresh: \(Self.dateFormatter.string(from: lastUpdatedAt))"
    }

    private func diagnosticStatusText(for diagnostic: IPTVSourceDiagnostic) -> String {
        if let errorMessage = diagnostic.errorMessage?.dragonTrimmedOrNil, !errorMessage.isEmpty {
            return "Error"
        }

        return diagnostic.downloadSucceeded ? "Ready" : "Failed"
    }

    private func diagnosticStatusColor(for diagnostic: IPTVSourceDiagnostic) -> Color {
        if diagnostic.errorMessage?.dragonTrimmedOrNil != nil {
            return DragonTheme.red
        }

        return diagnostic.downloadSucceeded ? .green : .gray
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}
