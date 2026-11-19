import AppCore
import SwiftUI

struct ItemEditorView: View {
    let items: ItemsModel
    let route: ItemRoute

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var saving = false
    @State private var loaded = false

    private var existing: Item? {
        if case .edit(let id) = route { return items.items.first { $0.id == id } }
        return nil
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                if let message = items.actionError?.fieldErrors["title"] { Text(message).font(.footnote).foregroundStyle(.red) }
                TextField("Notes", text: $text, axis: .vertical).lineLimit(3...8)
                if let message = items.actionError?.fieldErrors["body"] { Text(message).font(.footnote).foregroundStyle(.red) }
            }
            if let error = items.actionError, error.fieldErrors.isEmpty {
                Section { ErrorText(error: error) }
            }
            if let existing {
                Section {
                    LabeledContent("Created", value: existing.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Updated", value: existing.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    Button("Delete", role: .destructive) {
                        Task {
                            await items.delete(existing)
                            if items.actionError == nil { dismiss() }
                        }
                    }
                }
            }
        }
        .navigationTitle(existing == nil ? "New item" : "Edit item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(title.isEmpty || saving)
            }
        }
        .onAppear {
            items.dismissActionError()
            guard !loaded else { return }
            loaded = true
            title = existing?.title ?? ""
            text = existing?.body ?? ""
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let ok: Bool
        if let existing {
            ok = await items.update(existing, title: title, body: text)
        } else {
            ok = await items.create(title: title, body: text)
        }
        if ok { dismiss() }
    }
}
