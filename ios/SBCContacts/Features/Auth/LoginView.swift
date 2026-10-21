import SwiftUI

struct LoginView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ToastCenter.self) private var toasts

    @State private var authenticator = SSOAuthenticator()
    @State private var busy = false
    @State private var showCode = false
    @State private var code = ""
    @State private var networkAccount: NetworkAccountRoute?

    /// Which SBC Network form to open.
    private enum NetworkAccountRoute: Hashable, Identifiable {
        case create, signIn
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
        ScrollView {
            VStack(spacing: 0) {
                SBCLogo(height: 96)

                Text("Ton réseau SBC, directement dans ton téléphone.")
                    .font(.sbc(.bodyMedium))
                    .foregroundStyle(SBCColors.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)

                Capsule()
                    .fill(SBCColors.brandArc)
                    .frame(width: 120, height: 4)
                    .padding(.top, 16)

                Group {
                    if auth.isExchangingCode || busy {
                        ProgressView()
                            .controlSize(.large)
                            .frame(height: 52)
                    } else {
                        Button {
                            Task { await startSSO() }
                        } label: {
                            Label("Se connecter avec SBC", systemImage: "arrow.right.to.line")
                        }
                        .buttonStyle(FilledButtonStyle(minHeight: 52))
                    }
                }
                .padding(.top, 36)

                if let error = auth.loginError {
                    Text(loginErrorMessage(error))
                        .font(.sbc(.bodyMedium))
                        .foregroundStyle(SBCColors.error)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }

                if !(auth.isExchangingCode || busy) {
                    HStack(spacing: 12) {
                        Rectangle().fill(SBCColors.outlineVariant).frame(height: 1)
                        Text("ou avec SBC Network")
                            .font(.sbc(.bodySmall))
                            .foregroundStyle(SBCColors.onSurfaceVariant)
                            .fixedSize()
                        Rectangle().fill(SBCColors.outlineVariant).frame(height: 1)
                    }
                    .padding(.top, 24)

                    Button {
                        networkAccount = .create
                    } label: {
                        Label("Créer un compte SBC Network", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.outlined)
                    .padding(.top, 16)

                    Button("J'ai un compte SBC Network") { networkAccount = .signIn }
                        .buttonStyle(.text)
                        .padding(.top, 4)

                    Text("Tu veux plutôt un compte SBC ?")
                        .font(.sbc(.bodySmall))
                        .foregroundStyle(SBCColors.onSurfaceVariant)
                        .padding(.top, 12)
                    Button("Créer mon compte sur SBC") { Task { await signUpOnSBC() } }
                        .buttonStyle(.text)
                }

                // Fallback from before the in-app SSO session returned the code
                // itself. Kept for local testing only: in a release build it just
                // makes App Review ask where such a code comes from.
                #if DEBUG
                Button("J'ai un code d'autorisation") {
                    withAnimation { showCode.toggle() }
                }
                .buttonStyle(.text)
                .padding(.top, 12)

                if showCode {
                    VStack(spacing: 10) {
                        TextField("Colle le code reçu", text: $code)
                            .font(.sbc(.bodyLarge))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 14)
                            .frame(minHeight: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(SBCColors.outlineVariant)
                            )
                            .accessibilityLabel("Code SBC")
                        Button("Valider le code") {
                            Task { await submitCode() }
                        }
                        .buttonStyle(.outlined)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                #endif
            }
            .padding(28)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center) { length, _ in length }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SBCColors.background)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $networkAccount) { route in
            NetworkAccountView(create: route == .create)
        }
        }
    }

    private func startSSO() async {
        busy = true
        defer { busy = false }
        switch await authenticator.authorize() {
        case let .code(code):
            await auth.login(code: code)
        case .cancelled:
            break
        case let .failed(message):
            toasts.show(message)
        }
    }

    /// For whoever wants an SBC account rather than an SBC Network one: SBC's
    /// own sign-up page, opened in the same in-app session as sign-in.
    private func signUpOnSBC() async {
        busy = true
        defer { busy = false }
        await SSOAuthenticator.openSBCSignup()
        toasts.show("Compte SBC créé ? Touche « Se connecter avec SBC » pour entrer.")
    }

    private func submitCode() async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await auth.login(code: trimmed)
    }
}

#Preview {
    LoginView()
        .environment(AuthStore(repo: AppServices(storage: InMemoryTokenStorage()).auth))
        .environment(ToastCenter())
}
