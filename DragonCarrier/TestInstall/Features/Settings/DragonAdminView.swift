import SwiftUI

enum DragonAdminSection: String, CaseIterable, Identifiable {
    case tv
    case movies
    case youtube
    case articles
    case books
    case chess

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .tv:
            return "TV"
        case .movies:
            return "Movies"
        case .youtube:
            return "YouTube"
        case .articles:
            return "Articles"
        case .books:
            return "Books"
        case .chess:
            return "Chess"
        }
    }

    var adminTitle: String {
        "\(title) Admin"
    }

    var rootStatus: String {
        self == .tv ? "Functional" : "Placeholder"
    }

    var rootStatusColor: Color {
        self == .tv ? DragonTheme.red : .gray
    }

    var rootMessage: String {
        switch self {
        case .tv:
            return "Diagnostics and editable TV sources."
        default:
            return "Diagnostics and sources are not wired yet."
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
                                    Text(section == .tv ? "Open TV Admin" : "Open \(section.title) Admin")
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
        case .movies, .youtube, .articles, .books, .chess:
            DragonAdminSectionDetailView(section: section)
        }
    }
}
