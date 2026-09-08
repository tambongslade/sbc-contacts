/// A single review of a member (backend `ReviewView`).
class Review {
  const Review({
    required this.id,
    required this.memberSbcId,
    required this.stars,
    this.comment,
    this.reviewerName,
    this.reviewerAvatarUrl,
    this.isMine = false,
    this.createdAt,
    this.updatedAt,
  });

  factory Review.fromJson(Map<String, dynamic> json) => Review(
        id: (json['id'] ?? '').toString(),
        memberSbcId: (json['memberSbcId'] ?? '').toString(),
        stars: (json['stars'] as num?)?.toInt() ?? 0,
        comment: json['comment'] as String?,
        reviewerName: json['reviewerName'] as String?,
        reviewerAvatarUrl: json['reviewerAvatarUrl'] as String?,
        isMine: json['isMine'] as bool? ?? false,
        createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
        updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()),
      );

  final String id;
  final String memberSbcId;
  final int stars;
  final String? comment;
  final String? reviewerName;
  final String? reviewerAvatarUrl;
  final bool isMine;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get reviewerDisplayName =>
      (reviewerName == null || reviewerName!.isEmpty) ? 'Membre SBC' : reviewerName!;

  String get reviewerInitials {
    final n = reviewerDisplayName.trim();
    return n.isEmpty ? '?' : n[0].toUpperCase();
  }
}

/// Aggregate reputation for a member (backend `ScoreSummary`), returned
/// alongside the review list and after each write.
class ScoreSummary {
  const ScoreSummary({
    required this.memberSbcId,
    required this.averageStars,
    required this.reviewCount,
    required this.confidenceScore,
  });

  factory ScoreSummary.fromJson(Map<String, dynamic> json) => ScoreSummary(
        memberSbcId: (json['memberSbcId'] ?? '').toString(),
        averageStars: (json['averageStars'] as num?)?.toDouble() ?? 0,
        reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
        confidenceScore: (json['confidenceScore'] as num?)?.toInt() ?? 50,
      );

  final String memberSbcId;
  final double averageStars;
  final int reviewCount;
  final int confidenceScore;
}

/// A page of a member's reviews plus the aggregate and the caller's own review
/// (backend `MemberReviewsResult`).
class MemberReviews {
  const MemberReviews({
    required this.reviews,
    required this.summary,
    required this.hasMore,
    required this.page,
    this.myReview,
  });

  final List<Review> reviews;
  final ScoreSummary summary;
  final bool hasMore;
  final int page;
  final Review? myReview;
}
