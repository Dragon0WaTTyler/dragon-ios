import SwiftUI

struct DragonAdminSectionDetailView: View {
    let section: DragonAdminSection

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DragonTheme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    DragonAdminSectionCard(
                        title: "Diagnostics",
                        status: section.detailStatusTitle,
                        statusColor: section.detailStatusColor,
                        message: section.diagnosticsMessage
                    ) {
                        if let diagnosticsNote = section.diagnosticsNote {
                            Text(diagnosticsNote)
                                .font(.caption)
                                .foregroundStyle(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.black.opacity(0.28))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }

                    DragonAdminSectionCard(
                        title: "Sources",
                        status: section.detailStatusTitle,
                        statusColor: section.detailStatusColor,
                        message: section.sourcesMessage
                    ) {
                        if let sourcesNote = section.sourcesNote {
                            Text(sourcesNote)
                                .font(.caption)
                                .foregroundStyle(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.black.opacity(0.28))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
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
                Text(section.adminTitle)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)

                Text(section.detailHeaderMessage)
                    .font(.footnote)
                    .foregroundStyle(.gray)
            }

            Spacer()
        }
    }
}

private extension DragonAdminSection {
    var detailStatusTitle: String {
        self == .tv ? "Functional" : "Placeholder"
    }

    var detailStatusColor: Color {
        self == .tv ? DragonTheme.red : .gray
    }

    var detailHeaderMessage: String {
        switch self {
        case .dragonConnection:
            return "Legacy backend and connection admin shell for Dragon."
        case .movies:
            return "Local admin detail shell for Movies."
        case .articles:
            return "Local admin detail shell for Articles."
        case .youtube:
            return "Local admin detail shell for YouTube."
        case .books:
            return "Local admin detail shell for Books."
        case .tv:
            return "TV / IPTV diagnostics and source tools."
        case .developer:
            return "Local admin detail shell for developer-wide tools."
        }
    }

    var diagnosticsMessage: String {
        switch self {
        case .dragonConnection:
            return "Backend and legacy connection diagnostics are not wired in admin yet."
        case .movies:
            return "Movies diagnostics are not wired in iOS admin yet."
        case .articles:
            return "Articles diagnostics are not wired in iOS admin yet."
        case .youtube:
            return "YouTube diagnostics are not wired in iOS admin yet."
        case .books:
            return "Books diagnostics are not wired in iOS admin yet."
        case .tv:
            return "Use the TV admin screen for live diagnostics and cache tools."
        case .developer:
            return "App-level diagnostics are not wired in iOS admin yet."
        }
    }

    var sourcesMessage: String {
        switch self {
        case .dragonConnection:
            return "Connection source management is not wired in admin yet."
        case .movies:
            return "Movies source management is not wired in admin yet."
        case .articles:
            return "Articles source management is not wired in admin yet."
        case .youtube:
            return "YouTube source management is not wired in admin yet."
        case .books:
            return "Books source management is not wired in admin yet."
        case .tv:
            return "Use the TV admin screen for editable IPTV playlist sources."
        case .developer:
            return "Developer-level source controls are not wired in admin yet."
        }
    }

    var diagnosticsNote: String? {
        switch self {
        case .dragonConnection:
            return "The working legacy backend controls remain in Settings > Dragon Connection."
        case .movies:
            return "The live Notion token, source ID, and connection test remain in Settings > Movies."
        case .articles:
            return "The current RSS registry and article cache tools remain in Settings > Articles."
        case .youtube:
            return "No YouTube admin behavior was added in this task."
        case .books:
            return "No Books admin behavior was added in this task."
        case .tv:
            return nil
        case .developer:
            return "The current app-wide cache tools remain in Settings > Developer."
        }
    }

    var sourcesNote: String? {
        switch self {
        case .dragonConnection:
            return "This section is aligned with Settings, but no extra admin source editor exists yet."
        case .movies:
            return "No separate Movies admin source editor exists yet beyond the existing Settings flow."
        case .articles:
            return "No new RSS editor or sync logic was added here."
        case .youtube:
            return "This section stays as a placeholder until YouTube admin tools exist."
        case .books:
            return "This section stays as a placeholder until Books admin tools exist."
        case .tv:
            return nil
        case .developer:
            return "Use this placeholder to grow future developer-wide admin tools."
        }
    }
}
