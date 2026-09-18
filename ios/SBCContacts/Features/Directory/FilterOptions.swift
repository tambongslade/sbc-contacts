import Foundation

/// Filter vocabularies for the directory (cahier §6).
///
/// These are not guesses: they were sampled from the live SBC base (47,011
/// members) and must be sent verbatim. Two traps are encoded here —
///
///  * SBC stores professions and interests **unaccented** ("Macon", not
///    "Maçon"; "Cinema", not "Cinéma"). Sending the accented spelling matches
///    nothing, with no error to explain why.
///  * `sex` is "male"/"female"/"other", not "M"/"F".
///
/// Professions match partially and case-insensitively server-side, so a
/// free-typed fragment still works; the lists exist so a member can pick the
/// exact term instead of guessing it.
enum FilterOptions {
    struct Option: Sendable, Hashable {
        let code: String
        let label: String
    }

    /// Wire values for `sex`, with the label shown to the member.
    static let sexes: [Option] = [
        .init(code: "male", label: "Homme"),
        .init(code: "female", label: "Femme"),
        .init(code: "other", label: "Autre"),
    ]

    /// `country` is an ISO 3166-1 alpha-2 code on the wire, not a display name.
    static let countries: [Option] = [
        .init(code: "CM", label: "Cameroun"),
        .init(code: "CI", label: "Côte d'Ivoire"),
        .init(code: "TG", label: "Togo"),
        .init(code: "BJ", label: "Bénin"),
        .init(code: "CG", label: "Congo"),
        .init(code: "CD", label: "RD Congo"),
        .init(code: "SN", label: "Sénégal"),
        .init(code: "GA", label: "Gabon"),
        .init(code: "NE", label: "Niger"),
        .init(code: "ML", label: "Mali"),
        .init(code: "BF", label: "Burkina Faso"),
        .init(code: "TD", label: "Tchad"),
        .init(code: "CF", label: "Centrafrique"),
        .init(code: "GN", label: "Guinée"),
        .init(code: "FR", label: "France"),
        .init(code: "BE", label: "Belgique"),
        .init(code: "CA", label: "Canada"),
        .init(code: "US", label: "États-Unis"),
    ]

    static func sexLabel(_ code: String) -> String {
        sexes.first { $0.code == code }?.label ?? code
    }

    static func countryLabel(_ code: String) -> String {
        countries.first { $0.code == code }?.label ?? code
    }

    /// All 72 professions present in the base, most frequent first.
    static let professions: [String] = [
        "Etudiant(e)", "Sans emploi", "Etudiant·e", "Vendeur/Vendeuse", "Enseignant",
        "Electricien", "Macon", "Technicien en electronique", "Formateur professionnel",
        "Travailleur social", "Ingenieur civil", "Ingenieur en informatique",
        "Infirmier/Infirmiere", "Responsable marketing", "Agriculteur/Agricultrice",
        "Designer graphique", "Musicien", "Comptable", "Artiste (peintre, sculpteur)",
        "Medecin", "Plombier", "Charpentier", "Chef cuisinier", "Pharmacien",
        "Gestionnaire de produit", "Photographe", "Developpeur de logiciels", "Logisticien",
        "Ingenieur agronome", "Architecte", "Serveur/Serveuse",
        "Gestionnaire de ressources naturelles", "Charge de communication", "Biologiste",
        "Educateur specialise", "Dentiste", "Ecologiste", "Conducteur de train",
        "Analyste financier", "Ecrivain", "Realisateur", "Psychologue", "Chirurgien",
        "Avocat", "Chimiste", "Analyste de marche", "Ingenieur reseau",
        "Gestionnaire de communaute", "Gestionnaire d'hotel", "Administrateur systeme",
        "Barman/Barmane", "Consultant en strategie", "Architecte d'interieur",
        "Chercheur scientifique", "Journaliste", "Kinesitherapeute",
        "Conseiller en orientation", "Animateur socioculturel",
        "Consultant en technologies de l'information", "Scientifique des donnees",
        "Statisticien", "Conseiller pedagogique", "Juge", "Specialiste en cybersecurite",
        "Conseiller fiscal", "Gestionnaire de chaine d'approvisionnement",
        "Mediateur familial", "Auditeur interne", "Physicien", "Redacteur web",
        "Pilote d'avion", "Professeur d'universite",
    ]

    /// All 39 interests present in the base. Repeatable on the wire.
    static let interests: [String] = [
        "Football", "Musique (instruments, chant)", "Cinema", "Lecture", "Jeux video",
        "Tourisme local et international", "Basketball", "Photographie",
        "Apprentissage de nouvelles langues", "Programmation", "Danse", "Electronique",
        "Decouverte de nouvelles cultures", "Course a pied", "Cuisine du monde",
        "Sciences de la vie", "Fitness", "Aide aux personnes defavorisees",
        "Jeux de societe", "Patisserie", "Meditation", "Protection de l'environnement",
        "Nutrition", "Decoration d'interieur", "Medecine alternative", "Robotique",
        "Participation a des evenements caritatifs", "Peinture et dessin", "Theatre",
        "Artisanat", "Randonnees en nature", "Stylisme", "Natation",
        "Enigmes et casse-tetes", "Cyclisme", "Degustation de vins", "Randonnee",
        "Astronomie", "Yoga",
    ]

    /// One glyph per interest, so the chips are scannable by shape before they
    /// are read. Keys are the exact (unaccented) wire strings.
    static let interestEmoji: [String: String] = [
        "Football": "⚽", "Musique (instruments, chant)": "🎵", "Cinema": "🎬", "Lecture": "📚",
        "Jeux video": "🎮", "Tourisme local et international": "🧳", "Basketball": "🏀",
        "Photographie": "📷", "Apprentissage de nouvelles langues": "🗣", "Programmation": "💻",
        "Danse": "💃", "Electronique": "🔌", "Decouverte de nouvelles cultures": "🌍",
        "Course a pied": "🏃", "Cuisine du monde": "🍲", "Sciences de la vie": "🧬",
        "Fitness": "🏋", "Aide aux personnes defavorisees": "🤝", "Jeux de societe": "🎲",
        "Patisserie": "🧁", "Meditation": "🧘", "Protection de l'environnement": "🌱",
        "Nutrition": "🥗", "Decoration d'interieur": "🛋", "Medecine alternative": "🌿",
        "Robotique": "🤖", "Participation a des evenements caritatifs": "🎗",
        "Peinture et dessin": "🎨", "Theatre": "🎭", "Artisanat": "🧵",
        "Randonnees en nature": "🏕", "Stylisme": "👗", "Natation": "🏊",
        "Enigmes et casse-tetes": "🧩", "Cyclisme": "🚴", "Degustation de vins": "🍷",
        "Randonnee": "🥾", "Astronomie": "🔭", "Yoga": "🕊",
    ]

    /// Which country each région belongs to, so suggestions can be scoped to
    /// the pays already chosen. A set, because names genuinely collide:
    /// "Centre", "Est", "Nord" exist in both Cameroon and Burkina Faso.
    static let regionCountries: [String: Set<String>] = [
        "Centre": ["CM", "BF"], "Maritime": ["TG"], "Littoral": ["CM", "BJ"], "Abidjan": ["CI"],
        "Ouest": ["CM"], "Atlantique": ["BJ"], "Plateaux": ["TG"], "Brazzaville": ["CG"],
        "Ouémé": ["BJ"], "Kara": ["TG"], "Pointe-Noire": ["CG"], "Borgou": ["BJ"],
        "N'Djamena": ["TD"], "Centrale": ["TG"], "Dakar": ["SN"], "Est": ["CM", "BF"],
        "Hauts-Bassins": ["BF"], "Estuaire": ["GA"], "Niamey": ["NE"], "Nord": ["CM", "BF"],
        "Zou": ["BJ"], "Savanes": ["TG", "CI", "BF"], "Sud": ["CM"], "Mono": ["BJ"],
        "Bas-Sassandra": ["CI"], "Centre-Ouest": ["BF"], "Adamaoua": ["CM"], "Bamako": ["ML"],
        "Plateau": ["BJ"], "Couffo": ["BJ"], "Yamoussoukro": ["CI"], "Extrême-Nord": ["CM"],
        "Comoé": ["CI"], "Lagunes": ["CI"], "Collines": ["BJ"], "Sud-Ouest": ["CM", "BF"],
        "Centre-Est": ["BF"], "Boucle du Mouhoun": ["BF"], "Kadiogo": ["BF"], "Atacora": ["BJ"],
        "Alibori": ["BJ"], "Sassandra-Marahoué": ["CI"], "Donga": ["BJ"],
        "Vallée du Bandama": ["CI"], "Gôh-Djiboua": ["CI"], "Ogooué-Maritime": ["GA"],
        "Chari-Baguirmi": ["TD"], "Montagnes": ["CI"], "Kinshasa": ["CD"], "Zinder": ["NE"],
        "Centre-Nord": ["BF"], "Zanzan": ["CI"], "Bangui": ["CF"], "Haut-Katanga": ["CD"],
        "Haut-Ogooué": ["GA"], "Congo": ["CD"], "Ouaddaï": ["TD"], "Thiès": ["SN"],
        "Mayo-Kebbi Est": ["TD"], "Logone Occidental": ["TD"],
    ]

    /// Suggested régions for a pays, or all of them when none is chosen. Only
    /// that country's régions are offered — a country with no mapped région
    /// gets none, rather than a list from other countries that would match
    /// nothing once combined with it.
    static func regionsFor(_ countryCode: String?) -> [String] {
        regionsFor(countries: countryCode.map { [$0] } ?? [])
    }

    /// Régions belonging to any of `countries` (all of them when empty).
    static func regionsFor(countries: Set<String>) -> [String] {
        guard !countries.isEmpty else { return topRegions }
        return topRegions.filter { !(regionCountries[$0]?.isDisjoint(with: countries) ?? true) }
    }

    /// True when a région is plausible for the pays. Free-typed régions (598 of
    /// 658 are outside the table) are left alone.
    static func regionMatchesCountry(_ region: String, _ countryCode: String?) -> Bool {
        regionMatches(region, countries: countryCode.map { [$0] } ?? [])
    }

    /// True when a région belongs to at least one of `countries`.
    static func regionMatches(_ region: String, countries: Set<String>) -> Bool {
        guard !countries.isEmpty, let owners = regionCountries[region] else { return true }
        return !owners.isDisjoint(with: countries)
    }

    /// The 60 most common of 658 regions. Because the tail is long and spans
    /// many countries, region is offered as autocomplete over these plus free
    /// text — a fixed dropdown would hide 598 valid values.
    static let topRegions: [String] = [
        "Centre", "Maritime", "Littoral", "Abidjan", "Ouest", "Atlantique", "Plateaux",
        "Brazzaville", "Ouémé", "Kara", "Pointe-Noire", "Borgou", "N'Djamena", "Centrale",
        "Dakar", "Est", "Hauts-Bassins", "Estuaire", "Niamey", "Nord", "Zou", "Savanes",
        "Sud", "Mono", "Bas-Sassandra", "Centre-Ouest", "Adamaoua", "Bamako", "Plateau",
        "Couffo", "Yamoussoukro", "Extrême-Nord", "Comoé", "Lagunes", "Collines",
        "Sud-Ouest", "Centre-Est", "Boucle du Mouhoun", "Kadiogo", "Atacora", "Alibori",
        "Sassandra-Marahoué", "Donga", "Vallée du Bandama", "Gôh-Djiboua",
        "Ogooué-Maritime", "Chari-Baguirmi", "Montagnes", "Kinshasa", "Zinder",
        "Centre-Nord", "Zanzan", "Bangui", "Haut-Katanga", "Haut-Ogooué", "Congo",
        "Ouaddaï", "Thiès", "Mayo-Kebbi Est", "Logone Occidental",
    ]
}
