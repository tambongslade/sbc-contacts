/// Suggestion lists for the directory filters (cahier §6).
///
/// SBC exposes no facets endpoint, so these are curated seeds rather than a
/// live vocabulary: they let a member pick instead of guessing spelling, which
/// is the whole point — a typo in a free-text field silently returns nothing.
/// Every field still accepts free text, so a value missing here is not a dead
/// end. Replace these with a `GET /directory/facets` over the Member mirror
/// once that exists, and keep them as the offline fallback.
class FilterOptions {
  const FilterOptions._();

  /// SBC's base is Cameroonian first, then the rest of the francophone région.
  static const List<String> countries = [
    'Cameroun', "Côte d'Ivoire", 'Sénégal', 'Gabon', 'Congo',
    'RD Congo', 'Bénin', 'Togo', 'Burkina Faso', 'Mali', 'Niger', 'Tchad',
    'Centrafrique', 'Guinée', 'France', 'Belgique', 'Canada', 'États-Unis',
  ];

  /// Cities keyed by country; Cameroon is deliberately the detailed one.
  static const Map<String, List<String>> citiesByCountry = {
    'Cameroun': [
      'Yaoundé', 'Douala', 'Bafoussam', 'Bamenda', 'Garoua', 'Maroua',
      'Ngaoundéré', 'Bertoua', 'Buea', 'Limbe', 'Kribi', 'Ebolowa',
      'Dschang', 'Kumba', 'Edéa', 'Nkongsamba',
    ],
    "Côte d'Ivoire": ['Abidjan', 'Yamoussoukro', 'Bouaké', 'San-Pédro'],
    'Sénégal': ['Dakar', 'Thiès', 'Saint-Louis', 'Touba'],
    'Gabon': ['Libreville', 'Port-Gentil'],
    'Congo': ['Brazzaville', 'Pointe-Noire'],
    'RD Congo': ['Kinshasa', 'Lubumbashi', 'Goma'],
    'France': ['Paris', 'Lyon', 'Marseille', 'Lille', 'Toulouse'],
  };

  /// Includes the cahier's own worked examples (Maçon, Designer).
  static const List<String> professions = [
    'Agriculteur', 'Architecte', 'Avocat', 'Boulanger', 'Chauffeur',
    'Coiffeur', 'Commerçant', 'Comptable', 'Couturier', 'Cuisinier',
    'Designer', 'Développeur', 'Électricien', 'Enseignant', 'Entrepreneur',
    'Étudiant', 'Infirmier', 'Ingénieur', 'Journaliste', 'Maçon',
    'Marketeur', 'Mécanicien', 'Médecin', 'Menuisier', 'Notaire',
    'Photographe', 'Plombier', 'Restaurateur',
    'Secrétaire', 'Soudeur', 'Technicien', 'Traducteur', 'Transporteur',
    'Vendeur', 'Webdesigner',
  ];

  /// Includes the cahier's examples (Business, Marketing digital).
  static const List<String> interests = [
    'Business', 'Marketing digital', 'Immobilier', 'Agriculture',
    'Technologie', 'Finance', 'Formation', 'Import-Export', 'Mode',
    'Santé', 'Sport', 'Musique', 'Voyage', 'Restauration',
    'Transport', 'Énergie', 'Éducation', 'Artisanat',
  ];

  /// Cities for [country], falling back to every known city when the country
  /// is unset or unknown — so the picker is never empty.
  static List<String> citiesFor(String? country) {
    if (country != null && citiesByCountry.containsKey(country)) {
      return citiesByCountry[country]!;
    }
    return [
      for (final list in citiesByCountry.values) ...list,
    ]..sort();
  }
}
