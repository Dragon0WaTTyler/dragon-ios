import SwiftUI

enum DragonAdminSection: String, CaseIterable, Identifiable {
    case dragonConnection
    case movies
    case articles
    case youtube
    case books
    case tv
    case developer

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .dragonConnection:
            return "Dragon Connection"
        case .movies:
            return "Movies"
        case .articles:
            return "Articles"
        case .youtube:
            return "YouTube"
        case .books:
            return "Books"
        case .tv:
            return "TV / IPTV"
        case .developer:
            return "Developer"
        }
    }

    var adminTitle: String {
        switch self {
        case .developer:
            return "Developer Admin"
        default:
            return "\(title) Admin"
        }
    }

    var rootStatus: String {
        switch self {
        case .tv:
            return "Functional"
        case .dragonConnection, .movies, .articles, .youtube, .books, .developer:
            return "Placeholder"
        }
    }

    var rootStatusColor: Color {
        self == .tv ? DragonTheme.red : .gray
    }

    var rootMessage: String {
        switch self {
        case .dragonConnection:
            return "Legacy connection diagnostics and admin hooks can live here later."
        case .movies:
            return "Movies admin and source diagnostics are not wired yet."
        case .articles:
            return "Articles source diagnostics and admin tools are not wired yet."
        case .youtube:
            return "YouTube diagnostics and sources are not wired yet."
        case .books:
            return "Books diagnostics and sources are not wired yet."
        case .tv:
            return "Diagnostics and editable TV sources."
        case .developer:
            return "App-level diagnostics and developer tooling can expand here later."
        }
    }

    var openButtonTitle: String {
        switch self {
        case .tv:
            return "Open TV Admin"
        case .developer:
            return "Open Developer Admin"
        default:
            return "Open \(title) Admin"
        }
    }
}

struct DragonAdminView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DragonTheme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    ForEach(DragonAdminSection.allCases) { section in
                        NavigationLink {
                            destination(for: section)
                        } label: {
                            DragonAdminSectionCard(
                                title: section.title,
                                status: section.rootStatus,
                                statusColor: section.rootStatusColor,
                                message: section.rootMessage
                            ) {
                                HStack {
                                    Text(section.openButtonTitle)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.72))
                                }
                                .padding()
                                .background(Color.black.opacity(0.28))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        }
                        .buttonStyle(.plain)
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
                Text("Dragon Admin")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)

                Text("Choose a section to manage local diagnostics and sources.")
                    .font(.footnote)
                    .foregroundStyle(.gray)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func destination(for section: DragonAdminSection) -> some View {
        switch section {
        case .tv:
            DragonTVAdminView()
        case .dragonConnection, .movies, .articles, .youtube, .books, .developer:
            DragonAdminSectionDetailView(section: section)
        }
    }
}
