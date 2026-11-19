import AppCore
import SwiftUI

struct SignInView: View {
    let model: AppModel
    let reason: SignedOutReason

    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var creatingAccount = false

    var body: some View {
        NavigationStack {
            Form {
                if let notice {
                    Section { Label(notice, systemImage: "info.circle").foregroundStyle(.secondary) }
                }
                Section {
                    TextField("E-mail", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if creatingAccount {
                        TextField("Name", text: $name).textContentType(.name)
                    }
                    SecureField("Password", text: $password)
                        .textContentType(creatingAccount ? .newPassword : .password)
                }
                if let error = model.lastError {
                    Section { ErrorText(error: error) }
                }
                Section {
                    Button(creatingAccount ? "Create account" : "Sign in") { Task { await submit() } }
                        .disabled(!canSubmit)
                    Button(creatingAccount ? "I already have an account" : "Create an account (local development)") {
                        creatingAccount.toggle()
                        model.dismissError()
                    }
                    .font(.footnote)
                }
            }
            .navigationTitle(creatingAccount ? "Create account" : "Sign in")
            .overlay { if model.isWorking { ProgressView() } }
            .disabled(model.isWorking)
        }
    }

    private var canSubmit: Bool {
        !email.isEmpty && password.count >= 8 && (!creatingAccount || !name.isEmpty)
    }

    private var notice: String? {
        switch reason {
        case .none: nil
        case .sessionEnded: "Your session has ended. Please sign in again."
        case .notRevokedOnServer: "You are signed out on this device, but the server could not be told. The session there ends when it expires."
        }
    }

    private func submit() async {
        if creatingAccount {
            await model.signUp(email: email, password: password, name: name)
        } else {
            await model.signIn(email: email, password: password)
        }
        password = ""  // never keep the password longer than the request
    }
}

struct ErrorText: View {
    let error: AppError

    var body: some View {
        Label(error.message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .font(.callout)
            .accessibilityIdentifier("error-message")
    }
}
