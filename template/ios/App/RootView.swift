import AppCore
import SwiftUI

/// Chooses the screen from the authentication state. Nothing else decides who sees what.
struct RootView: View {
    let model: AppModel

    var body: some View {
        Group {
            switch model.state {
            case .launching:
                ProgressView("Starting…").task { await model.restore() }
            case .signedOut(let reason):
                SignInView(model: model, reason: reason)
            case .signedIn(let session):
                SignedInView(model: model, session: session)
            case .unconfirmed(let error):
                ContentUnavailableView {
                    Label("Can't reach the server", systemImage: "wifi.slash")
                } description: {
                    Text(error.message)
                } actions: {
                    Button("Try again") { Task { await model.restore() } }
                        .buttonStyle(.borderedProminent)
                    Button("Sign out on this device", role: .destructive) { Task { await model.signOut() } }
                }
            }
        }
        .animation(.default, value: model.state)
    }
}
