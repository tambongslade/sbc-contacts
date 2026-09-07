import 'package:sbc_contacts/core/network/api_client.dart';
import 'package:sbc_contacts/core/network/paginated.dart';
import 'package:sbc_contacts/features/directory/domain/member.dart';

/// Combinable directory filters (cahier §6).
class SearchFilters {
  const SearchFilters({
    this.search,
    this.country,
    this.city,
    this.profession,
    this.sex,
    this.ageMin,
    this.ageMax,
    this.interests = const [],
  });

  final String? search;
  final String? country;
  final String? city;
  final String? profession;
  final String? sex;
  final int? ageMin;
  final int? ageMax;
  final List<String> interests;

  bool get isEmpty =>
      (search == null || search!.isEmpty) &&
      country == null &&
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
        if (city != null) 'city': city,
        if (profession != null) 'profession': profession,
        if (sex != null) 'sex': sex,
        if (ageMin != null) 'ageMin': ageMin,
        if (ageMax != null) 'ageMax': ageMax,
        if (interests.isNotEmpty) 'interests': interests,
      };

  SearchFilters copyWith({
    String? search,
    String? country,
    String? city,
    String? profession,
    String? sex,
    int? ageMin,
    int? ageMax,
    List<String>? interests,
    bool clearSearch = false,
  }) =>
      SearchFilters(
        search: clearSearch ? null : (search ?? this.search),
        country: country ?? this.country,
        city: city ?? this.city,
        profession: profession ?? this.profession,
        sex: sex ?? this.sex,
        ageMin: ageMin ?? this.ageMin,
        ageMax: ageMax ?? this.ageMax,
        interests: interests ?? this.interests,
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
