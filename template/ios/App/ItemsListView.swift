import AppCore
import SwiftUI

struct ItemsListView: View {
    let items: ItemsModel

    var body: some View {
        Group {
            switch items.phase {
            case .idle, .loading where items.items.isEmpty:
                ProgressView("Loading…")
            case .failed(let error) where items.items.isEmpty:
                ContentUnavailableView {
                    Label("Couldn't load items", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.message)
                } actions: {
                    Button("Try again") { Task { await items.load() } }
                }
            default:
                if items.isEmpty {
                    ContentUnavailableView("No items yet", systemImage: "tray", description: Text("Tap Add to create one."))
                } else {
                    List {
                        if let error = items.actionError {
                            ErrorText(error: error)
                        }
                        ForEach(items.items) { item in
                            NavigationLink(value: ItemRoute.edit(item.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.headline)
                                    if !item.body.isEmpty { Text(item.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                                }
                            }
                        }
                        .onDelete { offsets in
                            let doomed = offsets.map { items.items[$0] }
                            Task { for item in doomed { await items.delete(item) } }
                        }
                    }
                    .refreshable { await items.load() }
                }
            }
        }
        .accessibilityIdentifier("items-list")
    }
}
