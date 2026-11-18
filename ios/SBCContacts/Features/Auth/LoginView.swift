import SwiftUI

struct LoginView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ToastCenter.self) private var toasts

    @State private var authenticator = SSOAuthenticator()
    @State private var busy = false
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

                networkSignIn

                // SBC sign-in comes back, under the SBC Network accounts.
                if AppConfig.sbcLoginEnabled {
                    sbcSignIn
                }
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

    /// SBC Network accounts, the main way in.
    private var networkSignIn: some View {
        VStack(spacing: 0) {
            Button {
                networkAccount = .signIn
            } label: {
                Label("Se connecter", systemImage: "arrow.right.to.line")
            }
            .buttonStyle(FilledButtonStyle(minHeight: 52))
            .padding(.top, 36)
            .disabled(auth.isExchangingCode || busy)

            Button {
                networkAccount = .create
            } label: {
                Label("Créer un compte", systemImage: "person.badge.plus")
            }
            .buttonStyle(.outlined)
            .padding(.top, 12)
            .disabled(auth.isExchangingCode || busy)
        }
    }

    /// "Se connecter avec SBC", below the SBC Network buttons.
    private var sbcSignIn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Rectangle().fill(SBCColors.outlineVariant).frame(height: 1)
                Text("ou avec SBC")
                    .font(.sbc(.bodySmall))
                    .foregroundStyle(SBCColors.onSurfaceVariant)
                    .fixedSize()
                Rectangle().fill(SBCColors.outlineVariant).frame(height: 1)
            }
            .padding(.top, 24)

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
                    .buttonStyle(.outlined)
                }
            }
            .padding(.top, 16)

            if let error = auth.loginError {
                Text(loginErrorMessage(error))
                    .font(.sbc(.bodyMedium))
                    .foregroundStyle(SBCColors.error)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }

            if !(auth.isExchangingCode || busy) {
                Button("Créer mon compte sur SBC") { Task { await signUpOnSBC() } }
                    .buttonStyle(.text)
                    .padding(.top, 4)
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
}

#Preview {
    LoginView()
        .environment(AuthStore(repo: AppServices(storage: InMemoryTokenStorage()).auth))
        .environment(ToastCenter())
}
