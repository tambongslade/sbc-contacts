import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/features/directory/domain/member.dart';
import 'package:sbc_contacts/features/reviews/application/reviews_controller.dart';
import 'package:sbc_contacts/features/reviews/domain/review.dart';
import 'package:sbc_contacts/features/reviews/presentation/review_form_dialog.dart';
import 'package:sbc_contacts/shared/widgets/member_avatar.dart';
import 'package:sbc_contacts/shared/widgets/star_rating.dart';

/// The reviews block on a member profile: heading + "leave a review" action
/// (hidden on your own profile) + the list of reviews.
class ReviewsSection extends ConsumerWidget {
  const ReviewsSection({required this.member, required this.isOwnProfile, super.key});

  final Member member;
  final bool isOwnProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(reviewsControllerProvider(member.sbcId));
    final myReview = async.value?.myReview;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Avis', style: theme.textTheme.titleMedium),
            const Spacer(),
            if (!isOwnProfile)
              TextButton.icon(
                onPressed: () => showReviewForm(
                  context,
                  memberSbcId: member.sbcId,
                  memberName: member.displayName,
                  existing: myReview,
                ),
                icon: Icon(myReview == null ? Icons.rate_review_outlined : Icons.edit_outlined,
                    size: 18),
                label: Text(myReview == null ? 'Laisser un avis' : 'Modifier'),
              ),
          ],
        ),
        const Gap(8),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text(
            'Avis indisponibles',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          data: (data) {
            if (data.reviews.isEmpty) {
              return Text(
                'Aucun avis pour le moment.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              );
            }
            return Column(
              children: [
                for (final r in data.reviews)
                  _ReviewTile(
                    review: r,
                    onDelete: r.isMine
                        ? () => ref
                            .read(reviewsControllerProvider(member.sbcId).notifier)
                            .remove()
                        : null,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review, this.onDelete});

  final Review review;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MemberAvatar(
            initials: review.reviewerInitials,
            avatarUrl: review.reviewerAvatarUrl,
            radius: 18,
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        review.isMine ? 'Vous' : review.reviewerDisplayName,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    StarRatingDisplay(value: review.stars.toDouble(), size: 15),
                  ],
                ),
                if (review.comment != null && review.comment!.isNotEmpty) ...[
                  const Gap(3),
                  Text(review.comment!, style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Supprimer mon avis',
              icon: const Icon(Icons.delete_outline, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}
