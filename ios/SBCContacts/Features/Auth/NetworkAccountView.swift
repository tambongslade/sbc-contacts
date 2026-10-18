import SwiftUI

/// An SBC Network account: created here, it lives in SBC Network only — no
/// SBC account behind it. `create` opens the sign-up form, otherwise sign-in.
struct NetworkAccountView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.services) private var services

    @State var create: Bool
    @State private var name = ""
    @State private var country = "CM"
    @State private var phone = ""
    @State private var password = ""
    @State private var confirm = ""
    // What criteria and filters match on — what SBC holds for its own members.
    @State private var sex: String?
    @State private var birthDate: Date?
    @State private var region: String?
    @State private var profession: String?
    @State private var interests: Set<String> = []
    /// The régions the filters use; built in until the live list loads.
    @State private var regions: RegionsStore?
    @State private var showPassword = false
    @State private var busy = false
    @State private var error: String?

    /// International dialing codes for `FilterOptions.countries`, shown in front
    /// of the WhatsApp number. The backend completes the number the same way.
    static let dialCodes: [String: String] = [
        "CM": "237", "CI": "225", "TG": "228", "BJ": "229", "CG": "242", "CD": "243",
        "SN": "221", "GA": "241", "NE": "227", "ML": "223", "BF": "226", "TD": "235",
        "CF": "236", "GN": "224", "FR": "33", "BE": "32", "CA": "1", "US": "1",
    ]

    /// Why the form cannot be sent yet, or nil.
    private var problem: String? {
        if create, name.trimmed.count < 2 { return "Indique ton nom" }
        if create, region == nil { return "Choisis ta région" }
        if create, sex == nil { return "Indique ton sexe" }
        if create, birthDate == nil { return "Indique ta date de naissance" }
        if create, profession == nil { return "Choisis ta profession" }
        if create, interests.isEmpty { return "Choisis au moins un centre d'intérêt" }
        if phone.filter(\.isNumber).count < 6 { return "Numéro WhatsApp invalide" }
        if password.isEmpty { return "Indique ton mot de passe" }
        if create, password.count < 8 { return "Le mot de passe doit faire au moins 8 caractères" }
        if create, confirm != password { return "Les mots de passe ne correspondent pas" }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SBCLogo(height: 64)
                Text(create ? "Ton compte SBC Network" : "Connexion à SBC Network")
                    .font(.sbc(.titleLarge, weight: .heavy))
                    .padding(.top, 8)
                Text(create
                    ? "Il reste sur SBC Network : pas besoin de compte SBC."
                    : "Avec le numéro WhatsApp et le mot de passe de ton compte SBC Network.")
                    .font(.sbc(.bodyMedium))
                    .foregroundStyle(SBCColors.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)

                if create {
                    OutlinedField(label: "Nom complet", systemImage: "person") {
                        TextField("Ex. Jean Paul Mbarga", text: $name)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                    }
                }
                OutlinedField(label: "Pays", systemImage: "globe") {
                    Picker("Pays", selection: $country) {
                        ForEach(FilterOptions.countries, id: \.code) { option in
                            Text(option.label).tag(option.code)
                        }
                    }
                    .labelsHidden()
                    .padding(.leading, -12) // the menu picker pads its label itself
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if create {
                    profileFields
                    sectionTitle("Ton compte", "Ton numéro WhatsApp et ton mot de passe servent à te connecter.")
                }
                OutlinedField(label: "Numéro WhatsApp", systemImage: "phone") {
                    HStack(spacing: 6) {
                        Text("+\(Self.dialCodes[country] ?? "")")
                            .foregroundStyle(SBCColors.onSurfaceVariant)
                        TextField("6 70 00 00 00", text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                    }
                }
                OutlinedField(label: "Mot de passe", systemImage: "lock") {
                    HStack {
                        Group {
                            if showPassword {
                                TextField(create ? "Au moins 8 caractères" : "Mot de passe", text: $password)
                            } else {
                                SecureField(create ? "Au moins 8 caractères" : "Mot de passe", text: $password)
                            }
                        }
                        .textContentType(create ? .newPassword : .password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        Button { showPassword.toggle() } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                        }
                        .accessibilityLabel(showPassword ? "Masquer" : "Afficher")
                        .foregroundStyle(SBCColors.onSurfaceVariant)
                    }
                    .padding(.trailing, 12)
                }
                if create {
                    OutlinedField(label: "Confirme le mot de passe", systemImage: "lock") {
                        Group {
                            if showPassword {
                                TextField("Retape-le", text: $confirm)
                            } else {
                                SecureField("Retape-le", text: $confirm)
                            }
                        }
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }
                }

                if let error {
                    Text(error)
                        .font(.sbc(.bodyMedium))
                        .foregroundStyle(SBCColors.error)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await submit() }
                } label: {
                    if busy { ProgressView().tint(.white) } else { Text(create ? "Créer mon compte" : "Se connecter") }
                }
                .buttonStyle(FilledButtonStyle(minHeight: 52))
                .disabled(busy)
                .padding(.top, 8)

                Button(create ? "J'ai déjà un compte SBC Network" : "Pas encore de compte ? Créer un compte") {
                    withAnimation {
                        create.toggle()
                        error = nil
                    }
                }
                .buttonStyle(.text)
                .disabled(busy)
            }
            .font(.sbc(.bodyLarge))
            .foregroundStyle(SBCColors.onSurface)
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(SBCColors.background)
        .onChange(of: country) { region = nil } // a région belongs to one country
        .task {
            let store = RegionsStore(repo: services.directory)
            regions = store
            await store.loadIfNeeded()
        }
        .navigationTitle(create ? "Créer un compte" : "Se connecter")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var regionOptions: [String] {
        (regions?.catalog ?? RegionCatalog.builtIn).regions(for: [country])
    }

    private func sectionTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.sbc(.titleMedium, weight: .bold))
            Text(subtitle).font(.sbc(.bodySmall)).foregroundStyle(SBCColors.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    /// Région, sexe, âge, profession and centres d'intérêt: the profile the
    /// criteria and the Vues WhatsApp filters match on.
    @ViewBuilder
    private var profileFields: some View {
        sectionTitle("Ton profil", "Pour que les bons membres te trouvent, et toi eux.")
        OutlinedField(label: "Région", systemImage: "mappin.and.ellipse") {
            Picker("Région", selection: $region) {
                Text("Choisir").tag(String?.none)
                ForEach(regionOptions, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .labelsHidden()
            .padding(.leading, -12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Sexe").font(.sbc(.labelLarge))
            FlowLayout(spacing: 8) {
                ForEach(FilterOptions.sexes, id: \.code) { option in
                    SelectableChip(label: option.label, selected: sex == option.code) { sex = option.code }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        OutlinedField(label: "Date de naissance", systemImage: "birthday.cake") {
            if let birthDate {
                DatePicker("Date de naissance", selection: Binding { birthDate } set: { self.birthDate = $0 },
                           in: Self.birthRange, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button("Choisir") {
                    birthDate = Calendar.current.date(byAdding: .year, value: -25, to: .now)
                }
                .foregroundStyle(SBCColors.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        OutlinedField(label: "Profession", systemImage: "briefcase") {
            Picker("Profession", selection: $profession) {
                Text("Choisir").tag(String?.none)
                ForEach(FilterOptions.professions, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .labelsHidden()
            .padding(.leading, -12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Centres d'intérêt").font(.sbc(.labelLarge))
            FlowLayout(spacing: 8) {
                ForEach(FilterOptions.interests, id: \.self) { interest in
                    SelectableChip(label: interest, selected: interests.contains(interest)) {
                        if interests.contains(interest) { interests.remove(interest) } else { interests.insert(interest) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 13 to 100 years ago, like the server accepts.
    private static var birthRange: ClosedRange<Date> {
        let calendar = Calendar.current
        return calendar.date(byAdding: .year, value: -100, to: .now)!...calendar.date(byAdding: .year, value: -13, to: .now)!
    }

    private func submit() async {
        if let problem {
            error = problem
            return
        }
        error = nil
        busy = true
        defer { busy = false }
        do {
            if create, let sex, let birthDate, let region, let profession {
                try await auth.register(.init(
                    name: name.trimmed,
                    country: country,
                    phoneNumber: phone.trimmed,
                    password: password,
                    sex: sex,
                    birthDate: Self.day.string(from: birthDate),
                    region: region,
                    profession: profession,
                    interests: FilterOptions.interests.filter(interests.contains)
                ))
            } else {
                try await auth.loginWithPhone(country: country, phoneNumber: phone.trimmed, password: password)
            }
            // Signed in: the root leaves the login flow on its own.
        } catch let apiError as APIError {
            error = apiError.message
        } catch {
            self.error = "Échec. Vérifie ta connexion et réessaie."
        }
    }
}
