import 'package:sbc_contacts/core/network/api_client.dart';
import 'package:sbc_contacts/features/reviews/domain/review.dart';

class ReviewsRepository {
  ReviewsRepository(this._api);
  final ApiClient _api;

  /// A page of reviews for a member, with the aggregate score and the caller's
  /// own review (backend `MemberReviewsResult`).
  Future<MemberReviews> list(String memberSbcId, {int page = 1, int limit = 20}) async {
    final data = await _api.get('/reviews/$memberSbcId', query: {'page': page, 'limit': limit})
        as Map<String, dynamic>;
    final items = (data['items'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(Review.fromJson)
        .toList();
    final my = data['myReview'];
    return MemberReviews(
      reviews: items,
      summary: ScoreSummary.fromJson(data['summary'] as Map<String, dynamic>? ?? const {}),
      hasMore: data['hasMore'] as bool? ?? false,
      page: (data['page'] as num?)?.toInt() ?? page,
      myReview: my is Map<String, dynamic> ? Review.fromJson(my) : null,
    );
  }

  /// Create or update the caller's review (upsert). Returns the fresh aggregate.
  Future<ScoreSummary> submit(String memberSbcId, {required int stars, String? comment}) async {
    final data = await _api.post('/reviews', body: {
      'memberSbcId': memberSbcId,
      'stars': stars,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    }) as Map<String, dynamic>;
    return ScoreSummary.fromJson(data['summary'] as Map<String, dynamic>? ?? const {});
  }

  /// Delete the caller's own review. Returns the fresh aggregate.
  Future<ScoreSummary> remove(String memberSbcId) async {
    final data = await _api.delete('/reviews/$memberSbcId') as Map<String, dynamic>;
    return ScoreSummary.fromJson(data);
  }
}
