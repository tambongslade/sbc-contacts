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
class FilterOptions {
  const FilterOptions._();

  /// Wire values for `sex`, with the label shown to the member.
  static const Map<String, String> sexes = {
    'male': 'Homme',
    'female': 'Femme',
    'other': 'Autre',
  };

  /// `country` is an ISO 3166-1 alpha-2 code on the wire, not a display name.
  static const Map<String, String> countries = {
    'CM': 'Cameroun',
    'CI': "Côte d'Ivoire",
    'TG': 'Togo',
    'BJ': 'Bénin',
    'CG': 'Congo',
    'CD': 'RD Congo',
    'SN': 'Sénégal',
    'GA': 'Gabon',
    'NE': 'Niger',
    'ML': 'Mali',
    'BF': 'Burkina Faso',
    'TD': 'Tchad',
    'CF': 'Centrafrique',
    'GN': 'Guinée',
    'FR': 'France',
    'BE': 'Belgique',
    'CA': 'Canada',
    'US': 'États-Unis',
  };

  /// All 72 professions present in the base, most frequent first.
  static const List<String> professions = [
    'Etudiant(e)',
    'Sans emploi',
    'Etudiant·e',
    'Vendeur/Vendeuse',
    'Enseignant',
    'Electricien',
    'Macon',
    'Technicien en electronique',
    'Formateur professionnel',
    'Travailleur social',
    'Ingenieur civil',
    'Ingenieur en informatique',
    'Infirmier/Infirmiere',
    'Responsable marketing',
    'Agriculteur/Agricultrice',
    'Designer graphique',
    'Musicien',
    'Comptable',
    'Artiste (peintre, sculpteur)',
    'Medecin',
    'Plombier',
    'Charpentier',
    'Chef cuisinier',
    'Pharmacien',
    'Gestionnaire de produit',
    'Photographe',
    'Developpeur de logiciels',
    'Logisticien',
    'Ingenieur agronome',
    'Architecte',
    'Serveur/Serveuse',
    'Gestionnaire de ressources naturelles',
    'Charge de communication',
    'Biologiste',
    'Educateur specialise',
    'Dentiste',
    'Ecologiste',
    'Conducteur de train',
    'Analyste financier',
    'Ecrivain',
    'Realisateur',
    'Psychologue',
    'Chirurgien',
    'Avocat',
    'Chimiste',
    'Analyste de marche',
    'Ingenieur reseau',
    'Gestionnaire de communaute',
    "Gestionnaire d'hotel",
    'Administrateur systeme',
    'Barman/Barmane',
    'Consultant en strategie',
    "Architecte d'interieur",
    'Chercheur scientifique',
    'Journaliste',
    'Kinesitherapeute',
    'Conseiller en orientation',
    'Animateur socioculturel',
    "Consultant en technologies de l'information",
    'Scientifique des donnees',
    'Statisticien',
    'Conseiller pedagogique',
    'Juge',
    'Specialiste en cybersecurite',
    'Conseiller fiscal',
    "Gestionnaire de chaine d'approvisionnement",
    'Mediateur familial',
    'Auditeur interne',
    'Physicien',
    'Redacteur web',
    "Pilote d'avion",
    "Professeur d'universite",
  ];

  /// All 39 interests present in the base. Repeatable on the wire.
  static const List<String> interests = [
    'Football',
    'Musique (instruments, chant)',
    'Cinema',
    'Lecture',
    'Jeux video',
    'Tourisme local et international',
    'Basketball',
    'Photographie',
    'Apprentissage de nouvelles langues',
    'Programmation',
    'Danse',
    'Electronique',
    'Decouverte de nouvelles cultures',
    'Course a pied',
    'Cuisine du monde',
    'Sciences de la vie',
    'Fitness',
    'Aide aux personnes defavorisees',
    'Jeux de societe',
    'Patisserie',
    'Meditation',
    "Protection de l'environnement",
    'Nutrition',
    "Decoration d'interieur",
    'Medecine alternative',
    'Robotique',
    'Participation a des evenements caritatifs',
    'Peinture et dessin',
    'Theatre',
    'Artisanat',
    'Randonnees en nature',
    'Stylisme',
    'Natation',
    'Enigmes et casse-tetes',
    'Cyclisme',
    'Degustation de vins',
    'Randonnee',
    'Astronomie',
    'Yoga',
  ];

  /// One glyph per interest, so the chips are scannable by shape before they
  /// are read. Interests are stored unaccented upstream, so the keys here are
  /// the exact wire strings from [interests]; a key that ever goes missing
  /// falls back to a neutral dot rather than breaking the chip.
  static const Map<String, String> interestEmoji = {
    'Football': '\u26BD',
    'Musique (instruments, chant)': '\u{1F3B5}',
    'Cinema': '\u{1F3AC}',
    'Lecture': '\u{1F4DA}',
    'Jeux video': '\u{1F3AE}',
    'Tourisme local et international': '\u{1F9F3}',
    'Basketball': '\u{1F3C0}',
    'Photographie': '\u{1F4F7}',
    'Apprentissage de nouvelles langues': '\u{1F5E3}',
    'Programmation': '\u{1F4BB}',
    'Danse': '\u{1F483}',
    'Electronique': '\u{1F50C}',
    'Decouverte de nouvelles cultures': '\u{1F30D}',
    'Course a pied': '\u{1F3C3}',
    'Cuisine du monde': '\u{1F372}',
    'Sciences de la vie': '\u{1F9EC}',
    'Fitness': '\u{1F3CB}',
    'Aide aux personnes defavorisees': '\u{1F91D}',
    'Jeux de societe': '\u{1F3B2}',
    'Patisserie': '\u{1F9C1}',
    'Meditation': '\u{1F9D8}',
    "Protection de l'environnement": '\u{1F331}',
    'Nutrition': '\u{1F957}',
    "Decoration d'interieur": '\u{1F6CB}',
    'Medecine alternative': '\u{1F33F}',
    'Robotique': '\u{1F916}',
    'Participation a des evenements caritatifs': '\u{1F397}',
    'Peinture et dessin': '\u{1F3A8}',
    'Theatre': '\u{1F3AD}',
    'Artisanat': '\u{1F9F5}',
    'Randonnees en nature': '\u{1F3D5}',
    'Stylisme': '\u{1F457}',
    'Natation': '\u{1F3CA}',
    'Enigmes et casse-tetes': '\u{1F9E9}',
    'Cyclisme': '\u{1F6B4}',
    'Degustation de vins': '\u{1F377}',
    'Randonnee': '\u{1F97E}',
    'Astronomie': '\u{1F52D}',
    'Yoga': '\u{1F54A}',
  };

  /// The 60 most common of 658 regions. Because the tail is long and spans
  /// many countries, region is offered as autocomplete over these plus free
  /// text — a fixed dropdown would hide 598 valid values.
  static const List<String> topRegions = [
    'Centre',
    'Maritime',
    'Littoral',
    'Abidjan',
    'Ouest',
    'Atlantique',
    'Plateaux',
    'Brazzaville',
    'Ouémé',
    'Kara',
    'Pointe-Noire',
    'Borgou',
    "N'Djamena",
    'Centrale',
    'Dakar',
    'Est',
    'Hauts-Bassins',
    'Estuaire',
    'Niamey',
    'Nord',
    'Zou',
    'Savanes',
    'Sud',
    'Mono',
    'Bas-Sassandra',
    'Centre-Ouest',
    'Adamaoua',
    'Bamako',
    'Plateau',
    'Couffo',
    'Yamoussoukro',
    'Extrême-Nord',
    'Comoé',
    'Lagunes',
    'Collines',
    'Sud-Ouest',
    'Centre-Est',
    'Boucle du Mouhoun',
    'Kadiogo',
    'Atacora',
    'Alibori',
    'Sassandra-Marahoué',
    'Donga',
    'Vallée du Bandama',
    'Gôh-Djiboua',
    'Ogooué-Maritime',
    'Chari-Baguirmi',
    'Montagnes',
    'Kinshasa',
    'Zinder',
    'Centre-Nord',
    'Zanzan',
    'Bangui',
    'Haut-Katanga',
    'Haut-Ogooué',
    'Congo',
    'Ouaddaï',
    'Thiès',
    'Mayo-Kebbi Est',
    'Logone Occidental',
  ];

  /// Which country each région belongs to, so the suggestions can be scoped to
  /// the pays already chosen.
  ///
  /// A set, not a single code, because the names genuinely collide: "Centre",
  /// "Est", "Nord" and "Sud-Ouest" are both Cameroonian and Burkinabè regions,
  /// "Littoral" is Cameroonian and Béninois, "Savanes" belongs to three
  /// countries. Scoping by country is what disambiguates them — which is also
  /// why a région alone is a weak filter.
  static const Map<String, Set<String>> regionCountries = {
    'Centre': {'CM', 'BF'},
    'Maritime': {'TG'},
    'Littoral': {'CM', 'BJ'},
    'Abidjan': {'CI'},
    'Ouest': {'CM'},
    'Atlantique': {'BJ'},
    'Plateaux': {'TG'},
    'Brazzaville': {'CG'},
    'Ouémé': {'BJ'},
    'Kara': {'TG'},
    'Pointe-Noire': {'CG'},
    'Borgou': {'BJ'},
    "N'Djamena": {'TD'},
    'Centrale': {'TG'},
    'Dakar': {'SN'},
    'Est': {'CM', 'BF'},
    'Hauts-Bassins': {'BF'},
    'Estuaire': {'GA'},
    'Niamey': {'NE'},
    'Nord': {'CM', 'BF'},
    'Zou': {'BJ'},
    'Savanes': {'TG', 'CI', 'BF'},
    'Sud': {'CM'},
    'Mono': {'BJ'},
    'Bas-Sassandra': {'CI'},
    'Centre-Ouest': {'BF'},
    'Adamaoua': {'CM'},
    'Bamako': {'ML'},
    'Plateau': {'BJ'},
    'Couffo': {'BJ'},
    'Yamoussoukro': {'CI'},
    'Extrême-Nord': {'CM'},
    'Comoé': {'CI'},
    'Lagunes': {'CI'},
    'Collines': {'BJ'},
    'Sud-Ouest': {'CM', 'BF'},
    'Centre-Est': {'BF'},
    'Boucle du Mouhoun': {'BF'},
    'Kadiogo': {'BF'},
    'Atacora': {'BJ'},
    'Alibori': {'BJ'},
    'Sassandra-Marahoué': {'CI'},
    'Donga': {'BJ'},
    'Vallée du Bandama': {'CI'},
    'Gôh-Djiboua': {'CI'},
    'Ogooué-Maritime': {'GA'},
    'Chari-Baguirmi': {'TD'},
    'Montagnes': {'CI'},
    'Kinshasa': {'CD'},
    'Zinder': {'NE'},
    'Centre-Nord': {'BF'},
    'Zanzan': {'CI'},
    'Bangui': {'CF'},
    'Haut-Katanga': {'CD'},
    'Haut-Ogooué': {'GA'},
    'Congo': {'CD'},
    'Ouaddaï': {'TD'},
    'Thiès': {'SN'},
    'Mayo-Kebbi Est': {'TD'},
    'Logone Occidental': {'TD'},
  };

  /// The suggested régions for [countryCode], or all of them when no pays is
  /// chosen. Falls back to the full list rather than an empty one: a country
  /// with no mapped région must not leave the member with nothing to pick.
  static List<String> regionsFor(String? countryCode) {
    if (countryCode == null) return topRegions;
    final scoped = topRegions
        .where((r) => regionCountries[r]?.contains(countryCode) ?? false)
        .toList();
    return scoped.isEmpty ? topRegions : scoped;
  }

  /// True when a région is plausible for the chosen pays. Used to drop a
  /// région that the member picked before switching country — the pair would
  /// match nothing, and silently returning zero results reads as a bug.
  static bool regionMatchesCountry(String region, String? countryCode) {
    if (countryCode == null) return true;
    final owners = regionCountries[region];
    // Free-typed régions are outside the table (598 of 658 are); leave them.
    return owners == null || owners.contains(countryCode);
  }
}
