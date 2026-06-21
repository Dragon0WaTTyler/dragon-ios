import SwiftUI

struct DragonTVAdminSourcesView: View {
    let sources: [DragonTVSource]
    let statusText: String
    let onSaveSource: (DragonTVSource) -> Void
    let onDeleteSource: (DragonTVSource) -> Void
    let onResetSources: () -> Void

    @State private var editorDraft: DragonTVSourceDraft?
    @State private var pendingDeleteSource: DragonTVSource?
    @State private var showResetConfirmation = false

    var body: some View {
        DragonAdminSectionCard(
            title: "Sources",
            status: statusText,
            statusColor: .gray,
            message: "Built-in defaults plus local overrides and custom sources."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if sources.isEmpty {
                    Text("No TV sources are configured.")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.28))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    ForEach(sources) { source in
                        sourceRow(source)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        editorDraft = .newCustomSource()
                    } label: {
                        Text("Add Custom Source")
                    }
                    .buttonStyle(DragonAdminFilledButtonStyle())

                    Button {
                        showResetConfirmation = true
                    } label: {
                        Text("Reset Defaults")
                    }
                    .buttonStyle(DragonAdminOutlineButtonStyle())
                }
            }
        }
        .sheet(item: $editorDraft) { draft in
            DragonTVSourceEditorView(draft: draft) { savedSource in
                onSaveSource(savedSource)
            }
        }
        .alert("Delete custom TV source?", isPresented: deleteConfirmationBinding) {
            Button("Delete", role: .destructive) {
                if let pendingDeleteSource {
                    onDeleteSource(pendingDeleteSource)
                }
                pendingDeleteSource = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteSource = nil
            }
        } message: {
            Text("This removes the custom source from local TV admin settings.")
        }
        .alert("Reset TV sources to defaults?", isPresented: $showResetConfirmation) {
            Button("Reset", role: .destructive) {
                onResetSources()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all built-in overrides and custom TV sources.")
        }
    }

    private func sourceRow(_ source: DragonTVSource) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(source.normalizedLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        Text(source.isBuiltIn ? "Built-in" : "Custom")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(source.isBuiltIn ? .white.opacity(0.82) : DragonTheme.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.24))
                            .clipShape(Capsule())
                    }

                    Text(source.normalizedURLString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.gray)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Toggle("", isOn: Binding(
                    get: { source.isEnabled },
                    set: { isEnabled in
                        onSaveSource(source.updating(isEnabled: isEnabled))
                    }
                ))
                .labelsHidden()
                .tint(DragonTheme.red)
            }

            HStack(spacing: 12) {
                Button {
                    editorDraft = DragonTVSourceDraft(source: source)
                } label: {
                    Text("Edit")
                }
                .buttonStyle(DragonAdminOutlineButtonStyle())

                if !source.isBuiltIn {
                    Button {
                        pendingDeleteSource = source
                    } label: {
                        Text("Delete")
                    }
                    .buttonStyle(DragonAdminOutlineButtonStyle())
                }
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteSource != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteSource = nil
                }
            }
        )
    }
}

private struct DragonTVSourceDraft: Identifiable {
    let id = UUID()
    let sourceID: String
    let isBuiltIn: Bool
    var label: String
    var urlString: String
    var isEnabled: Bool
    let isNewCustomSource: Bool

    init(source: DragonTVSource) {
        sourceID = source.id
        isBuiltIn = source.isBuiltIn
        label = source.label
        urlString = source.urlString
        isEnabled = source.isEnabled
        isNewCustomSource = false
    }

    private init(
        sourceID: String,
        isBuiltIn: Bool,
        label: String,
        urlString: String,
        isEnabled: Bool,
        isNewCustomSource: Bool
    ) {
        self.sourceID = sourceID
        self.isBuiltIn = isBuiltIn
        self.label = label
        self.urlString = urlString
        self.isEnabled = isEnabled
        self.isNewCustomSource = isNewCustomSource
    }

    static func newCustomSource() -> DragonTVSourceDraft {
        DragonTVSourceDraft(
            sourceID: "custom-\(UUID().uuidString.lowercased())",
            isBuiltIn: false,
            label: "",
            urlString: "",
            isEnabled: true,
            isNewCustomSource: true
        )
    }

    var title: String {
        isNewCustomSource ? "Add TV Source" : "Edit TV Source"
    }

    var saveButtonTitle: String {
        isNewCustomSource ? "Add Source" : "Save Changes"
    }
}

private struct DragonTVSourceEditorView: View {
    let draft: DragonTVSourceDraft
    let onSave: (DragonTVSource) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var urlString: String
    @State private var isEnabled: Bool
    @State private var validationError: String?

    init(draft: DragonTVSourceDraft, onSave: @escaping (DragonTVSource) -> Void) {
        self.draft = draft
        self.onSave = onSave
        _label = State(initialValue: draft.label)
        _urlString = State(initialValue: draft.urlString)
        _isEnabled = State(initialValue: draft.isEnabled)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DragonTheme.background.ignoresSafeArea()

                Form {
                    Section("Source") {
                        TextField("Label", text: $label)
                            .textInputAutocapitalization(.never)

                        TextField("https://example.com/playlist.m3u", text: $urlString)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.URL)

                        Toggle("Enabled", isOn: $isEnabled)
                            .tint(DragonTheme.red)
                    }

                    if let validationError {
                        Section("Validation") {
                            Text(validationError)
                                .font(.caption)
                                .foregroundStyle(DragonTheme.red)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.saveButtonTitle) {
                        save()
                    }
                    .foregroundStyle(.white)
                }
            }
            .navigationTitle(draft.title)
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
        }
    }

    private func save() {
        let trimmedURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let resolvedURL = URL(string: trimmedURLString),
              let scheme = resolvedURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            validationError = "Enter a valid http:// or https:// URL."
            return
        }

        let resolvedLabel = label.dragonTrimmedOrNil
            ?? resolvedURL.host?.dragonTrimmedOrNil
            ?? "TV Source"

        validationError = nil
        onSave(
            DragonTVSource(
                id: draft.sourceID,
                label: resolvedLabel,
                urlString: resolvedURL.absoluteString,
                isEnabled: isEnabled,
                isBuiltIn: draft.isBuiltIn
            )
        )
        dismiss()
    }
}
