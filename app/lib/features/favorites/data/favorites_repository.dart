import 'package:sbc_contacts/core/network/api_client.dart';
import 'package:sbc_contacts/core/network/paginated.dart';
import 'package:sbc_contacts/features/directory/domain/member.dart';

/// A favorited member (backend `FavoriteItem`) mapped onto [Member] for reuse.
Member _favoriteToMember(Map<String, dynamic> json) => Member(
      id: (json['memberSbcId'] ?? '').toString(),
      sbcId: (json['memberSbcId'] ?? '').toString(),
      name: json['name'] as String?,
      firstName: json['firstName'] as String?,
      profession: json['profession'] as String?,
      city: json['city'] as String?,
      country: json['country'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      isFavorite: true,
    );

class FavoritesRepository {
  FavoritesRepository(this._api);
  final ApiClient _api;

  Future<Paginated<Member>> list({int page = 1, int limit = 50}) async {
    final data = await _api.get('/favorites', query: {'page': page, 'limit': limit})
        as Map<String, dynamic>;
    return Paginated.fromJson(data, _favoriteToMember);
  }

  Future<void> add(String memberSbcId) =>
      _api.post('/favorites', body: {'memberSbcId': memberSbcId});

  Future<void> remove(String memberSbcId) => _api.delete('/favorites/$memberSbcId');
}
