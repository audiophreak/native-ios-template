import AppCore
import SwiftUI

struct SignedInView: View {
    let model: AppModel
    let session: SessionInfo

    @State private var items: ItemsModel
    @State private var showingSession = false

    init(model: AppModel, session: SessionInfo) {
        self.model = model
        self.session = session
        _items = State(initialValue: ItemsModel(api: model.environment.api))
    }

    var body: some View {
        NavigationStack {
            ItemsListView(items: items)
                .navigationTitle("Items")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Account", systemImage: "person.crop.circle") { showingSession = true }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink("Add", value: ItemRoute.new)
                    }
                }
                .navigationDestination(for: ItemRoute.self) { route in
                    ItemEditorView(items: items, route: route)
                }
                .sheet(isPresented: $showingSession) {
                    AccountView(model: model, session: session)
                }
        }
        .task { await items.load() }
    }
}

enum ItemRoute: Hashable {
    case new
    case edit(String)
}

struct AccountView: View {
    let model: AppModel
    let session: SessionInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Signed in as") {
                    LabeledContent("Name", value: session.user.name)
                    LabeledContent("E-mail", value: session.user.email)
                    LabeledContent("Session ends", value: session.expiresAt.formatted(date: .abbreviated, time: .shortened))
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        Task {
                            await model.signOut()
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("sign-out")
                }
            }
            .navigationTitle("Account")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
