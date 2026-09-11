import 'package:sbc_contacts/core/network/api_client.dart';
import 'package:sbc_contacts/core/network/paginated.dart';
import 'package:sbc_contacts/features/directory/domain/member.dart';

/// Combinable directory filters (cahier §6).
class SearchFilters {
  const SearchFilters({
    this.search,
    this.country,
    this.region,
    this.city,
    this.profession,
    this.sex,
    this.ageMin,
    this.ageMax,
    this.interests = const [],
    this.sortByConfidence = false,
  });

  final String? search;
  /// ISO 3166-1 alpha-2 (e.g. "CM"), not a display name.
  final String? country;

  /// The member's real location field in SBC — coarser than [city] and the
  /// one that actually has data (658 distinct values across countries).
  final String? region;
  final String? city;
  final String? profession;
  final String? sex;
  final int? ageMin;
  final int? ageMax;
  final List<String> interests;

  /// Order each page by "score de confiance" instead of SBC's own relevance
  /// order. Not counted as a filter: it changes the order of the results, not
  /// which members are in them.
  final bool sortByConfidence;

  bool get isEmpty =>
      (search == null || search!.isEmpty) &&
      country == null &&
      region == null &&
      city == null &&
      profession == null &&
      sex == null &&
      ageMin == null &&
      ageMax == null &&
      interests.isEmpty;

  Map<String, dynamic> toQuery(int page, int limit) => {
        'page': page,
        'limit': limit,
        if (search != null && search!.isNotEmpty) 'search': search,
        if (country != null) 'country': country,
        if (region != null) 'region': region,
        if (city != null) 'city': city,
        if (profession != null) 'profession': profession,
        if (sex != null) 'sex': sex,
        if (ageMin != null) 'ageMin': ageMin,
        if (ageMax != null) 'ageMax': ageMax,
        if (interests.isNotEmpty) 'interests': interests,
        if (sortByConfidence) 'sort': 'confidence',
      };

  SearchFilters copyWith({
    String? search,
    String? country,
    String? region,
    String? city,
    String? profession,
    String? sex,
    int? ageMin,
    int? ageMax,
    List<String>? interests,
    bool? sortByConfidence,
    bool clearSearch = false,
  }) =>
      SearchFilters(
        search: clearSearch ? null : (search ?? this.search),
        country: country ?? this.country,
        region: region ?? this.region,
        city: city ?? this.city,
        profession: profession ?? this.profession,
        sex: sex ?? this.sex,
        ageMin: ageMin ?? this.ageMin,
        ageMax: ageMax ?? this.ageMax,
        interests: interests ?? this.interests,
        sortByConfidence: sortByConfidence ?? this.sortByConfidence,
      );
}

class DirectoryRepository {
  DirectoryRepository(this._api);
  final ApiClient _api;

  Future<Paginated<Member>> search(SearchFilters filters, {int page = 1, int limit = 20}) async {
    final data = await _api.get('/directory/search', query: filters.toQuery(page, limit))
        as Map<String, dynamic>;
    return Paginated.fromJson(data, Member.fromJson);
  }

  Future<Member> profile(String sbcId) async =>
      Member.fromJson(await _api.get('/directory/members/$sbcId') as Map<String, dynamic>);
}
