import SwiftUI

struct DragonBooksView: View {
    @StateObject private var viewModel: DragonBooksViewModel
    @State private var searchText = ""

    init() {
        _viewModel = StateObject(wrappedValue: DragonBooksViewModel())
    }

    init(viewModel: DragonBooksViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DragonTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Books")
                                    .font(.system(size: 38, weight: .bold))
                                    .foregroundStyle(.white)

                                Text("Native reading snapshot")
                                    .font(.headline)
                                    .foregroundStyle(.gray)
                            }

                            Spacer()

                            Button {
                                Task {
                                    await viewModel.loadBooks()
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(DragonTheme.card)
                                    .clipShape(Circle())
                            }
                        }

                        if viewModel.response != nil {
                            DragonRefreshStatusView(
                                lastUpdatedAt: viewModel.lastUpdatedAt,
                                isRefreshing: viewModel.isLoading,
                                errorText: viewModel.refreshErrorText
                            )
                        }

                        switch viewModel.state {
                        case .idle:
                            BooksLoadingView()

                        case .loading where viewModel.books.isEmpty:
                            BooksLoadingView()

                        case .failed(let message):
                            BooksStateCard(
                                title: "Could not load books",
                                message: message,
                                buttonTitle: "Try Again"
                            ) {
                                await viewModel.loadBooks()
                            }

                        case .empty:
                            BooksStateCard(
                                title: "No books found.",
                                message: "Pull to refresh to check again.",
                                buttonTitle: "Reload"
                            ) {
                                await viewModel.loadBooks()
                            }

                        case .loaded, .loading:
                            if filteredBooks.isEmpty {
                                if viewModel.books.isEmpty {
                                    BooksStateCard(
                                        title: "No books found.",
                                        message: "Pull to refresh to check again.",
                                        buttonTitle: "Reload"
                                    ) {
                                        await viewModel.loadBooks()
                                    }
                                } else {
                                    NoMatchesView()
                                }
                            } else {
                                LazyVStack(spacing: 12) {
                                    ForEach(filteredBooks) { book in
                                        NavigationLink {
                                            BookDetailView(book: book)
                                        } label: {
                                            BookRow(book: book)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(24)
                    .padding(.bottom, 90)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search books")
        .refreshable {
            await viewModel.loadBooks()
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.loadBooks()
            }
        }
    }

    private var filteredBooks: [DragonBook] {
        let query = normalizedSearchText(searchText)
        guard !query.isEmpty else {
            return viewModel.books
        }

        return viewModel.books.filter { book in
            [
                book.title,
                book.author,
                book.authors.joined(separator: " "),
                book.excerpt
            ].contains { normalizedSearchText($0).contains(query) }
        }
    }

    private func normalizedSearchText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

struct BookRow: View {
    let book: DragonBook

    private var authorsText: String {
        let joined = book.authors.joined(separator: ", ").trimmingCharacters(in: .whitespacesAndNewlines)
        if !joined.isEmpty {
            return joined
        }
        return book.author.isEmpty ? "Unknown author" : book.author
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let coverURL = coverURL {
                    AsyncImage(url: coverURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure(_):
                            placeholderCover
                        case .empty:
                            placeholderCover
                        @unknown default:
                            placeholderCover
                        }
                    }
                } else {
                    placeholderCover
                }
            }
            .frame(width: 52, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 8) {
                Text(book.title.isEmpty ? "Untitled book" : book.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(authorsText)
                    .font(.subheadline)
                    .foregroundStyle(DragonTheme.red)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if !book.year.isEmpty {
                        Text(book.year)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }

                    if !book.status.isEmpty {
                        Text(book.status)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }

                    if !book.score.isEmpty {
                        Text(book.score)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                }

                if !book.excerpt.isEmpty {
                    Text(book.excerpt)
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(DragonTheme.red.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var coverURL: URL? {
        let trimmed = book.cover.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return URL(string: trimmed)
    }

    private var placeholderCover: some View {
        ZStack {
            Color.black.opacity(0.45)
            Image(systemName: "book.closed")
                .font(.title3)
                .foregroundStyle(DragonTheme.red)
        }
    }
}

struct BooksLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView()
                .tint(DragonTheme.red)

            Text("Loading books...")
                .foregroundStyle(.gray)
                .font(.footnote)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct BooksStateCard: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.gray)

            Button {
                Task {
                    await action()
                }
            } label: {
                Text(buttonTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(DragonTheme.red)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct BookDetailView: View {
    let book: DragonBook

    private var coverURL: URL? {
        let trimmed = book.cover.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return URL(string: trimmed)
    }

    private var authorsText: String {
        let authors = book.authors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !authors.isEmpty {
            return authors.joined(separator: ", ")
        }
        return book.author.isEmpty ? "Unknown author" : book.author
    }

    var body: some View {
        ZStack {
            DragonTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        BookCoverView(url: coverURL, size: CGSize(width: 92, height: 138))

                        VStack(alignment: .leading, spacing: 8) {
                            Text(book.title.isEmpty ? "Untitled book" : book.title)
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(.white)

                            Text(authorsText)
                                .font(.headline)
                                .foregroundStyle(DragonTheme.red)

                            if !book.status.isEmpty {
                                Text(book.status)
                                    .font(.subheadline)
                                    .foregroundStyle(.gray)
                            }
                        }
                    }

                    InfoBlock(title: "Year", value: book.year)
                    InfoBlock(title: "Score", value: book.score)
                    InfoBlock(title: "Excerpt", value: book.excerpt.isEmpty ? "No excerpt available." : book.excerpt)
                }
                .padding(24)
                .padding(.bottom, 90)
            }
        }
        .navigationTitle("Book")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BookCoverView: View {
    let url: URL?
    let size: CGSize

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DragonTheme.red.opacity(0.25), lineWidth: 1)
        )
    }

    private var placeholder: some View {
        ZStack {
            Color.black.opacity(0.45)
            Image(systemName: "book.closed")
                .font(.title2)
                .foregroundStyle(DragonTheme.red)
        }
    }
}

struct InfoBlock: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.gray)

            Text(value.isEmpty ? "Unavailable" : value)
                .font(.body)
                .foregroundStyle(.white)
                .lineSpacing(4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

#Preview("Books") {
    DragonBooksView(
        viewModel: DragonBooksViewModel(
            initialState: .loaded,
            initialResponse: .preview
        )
    )
}

#Preview("Book Detail") {
    NavigationStack {
        BookDetailView(book: DragonBooksResponse.preview.items[0])
    }
}
