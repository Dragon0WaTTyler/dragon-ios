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
                        status: "Placeholder",
                        statusColor: .gray,
                        message: "Not wired in iOS admin yet"
                    ) {
                        EmptyView()
                    }

                    DragonAdminSectionCard(
                        title: "Sources",
                        status: "Placeholder",
                        statusColor: .gray,
                        message: "Not wired in iOS admin yet"
                    ) {
                        EmptyView()
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

                Text("Local admin detail shell for \(section.title).")
                    .font(.footnote)
                    .foregroundStyle(.gray)
            }

            Spacer()
        }
    }
}
