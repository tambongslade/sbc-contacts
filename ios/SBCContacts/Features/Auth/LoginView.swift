import SwiftUI

struct LoginView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ToastCenter.self) private var toasts

    @State private var authenticator = SSOAuthenticator()
    @State private var busy = false
    @State private var showCode = false
    @State private var code = ""
    @State private var showSignup = false
    @State private var sponsor = ""

    var body: some View {
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
                    Button {
                        withAnimation { showSignup.toggle() }
                    } label: {
                        Label("Créer un compte", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.outlined)
                    .padding(.top, 12)

                    if showSignup {
                        VStack(spacing: 10) {
                            TextField("Code parrain (facultatif)", text: $sponsor)
                                .font(.sbc(.bodyLarge))
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 14)
                                .frame(minHeight: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(SBCColors.outlineVariant)
                                )
                            Text("Le code de la personne qui t'a invité. Tu peux le laisser vide.")
                                .font(.sbc(.bodySmall))
                                .foregroundStyle(SBCColors.onSurfaceVariant)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Continuer l'inscription sur SBC") {
                                Task { await startSignup() }
                            }
                            .buttonStyle(FilledButtonStyle(minHeight: 48))
                        }
                        .padding(.top, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

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
            }
            .padding(28)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center) { length, _ in length }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SBCColors.background)
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

    /// App accounts are SBC accounts: sign-up (OTP, sponsor, subscription)
    /// happens on SBC's own page, opened inside the app.
    private func startSignup() async {
        busy = true
        defer { busy = false }
        await authenticator.signUp(sponsorCode: sponsor.trimmingCharacters(in: .whitespacesAndNewlines))
        showSignup = false
        toasts.show("Compte créé ? Touche « Se connecter avec SBC » pour entrer.")
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
