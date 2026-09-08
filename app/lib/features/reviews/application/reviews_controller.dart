import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/features/directory/presentation/profile_screen.dart';
import 'package:sbc_contacts/features/reviews/domain/review.dart';

/// The reviews + aggregate score for one member, keyed by SBC id. Writes go
/// through here so the profile's confidence badge refreshes with the list.
class ReviewsController extends AsyncNotifier<MemberReviews> {
  ReviewsController(this.memberSbcId);

  /// The family argument this notifier was built for.
  final String memberSbcId;

  @override
  FutureOr<MemberReviews> build() {
    return ref.watch(reviewsRepositoryProvider).list(memberSbcId);
  }

  /// Create or update the caller's review, then refresh the list and the
  /// member profile (so the score badge updates in place).
  Future<void> submit({required int stars, String? comment}) async {
    await ref.read(reviewsRepositoryProvider).submit(memberSbcId, stars: stars, comment: comment);
    ref.invalidate(memberProfileProvider(memberSbcId));
    ref.invalidateSelf();
  }

  /// Delete the caller's own review, then refresh.
  Future<void> remove() async {
    await ref.read(reviewsRepositoryProvider).remove(memberSbcId);
    ref.invalidate(memberProfileProvider(memberSbcId));
    ref.invalidateSelf();
  }
}

final reviewsControllerProvider =
    AsyncNotifierProvider.family<ReviewsController, MemberReviews, String>(
  ReviewsController.new,
);
