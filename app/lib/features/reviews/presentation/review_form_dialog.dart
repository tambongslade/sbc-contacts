import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/features/reviews/application/reviews_controller.dart';
import 'package:sbc_contacts/features/reviews/domain/review.dart';
import 'package:sbc_contacts/shared/widgets/star_rating.dart';

/// Bottom-sheet form to create or edit the caller's review of [memberSbcId].
/// Pre-filled from [existing] when editing.
Future<void> showReviewForm(
  BuildContext context, {
  required String memberSbcId,
  required String memberName,
  Review? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReviewForm(
      memberSbcId: memberSbcId,
      memberName: memberName,
      existing: existing,
    ),
  );
}

class _ReviewForm extends ConsumerStatefulWidget {
  const _ReviewForm({
    required this.memberSbcId,
    required this.memberName,
    this.existing,
  });

  final String memberSbcId;
  final String memberName;
  final Review? existing;

  @override
  ConsumerState<_ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends ConsumerState<_ReviewForm> {
  late int _stars = widget.existing?.stars ?? 0;
  late final TextEditingController _comment =
      TextEditingController(text: widget.existing?.comment ?? '');
  bool _submitting = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(reviewsControllerProvider(widget.memberSbcId).notifier)
          .submit(stars: _stars, comment: _comment.text.trim());
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Avis enregistré')));
    } catch (e) {
      setState(() => _submitting = false);
      messenger.showSnackBar(SnackBar(content: Text('Échec: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isEdit ? 'Modifier mon avis' : 'Laisser un avis',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const Gap(4),
          Text(
            widget.memberName,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const Gap(12),
          StarRatingInput(
            value: _stars,
            onChanged: (v) => setState(() => _stars = v),
          ),
          const Gap(12),
          TextField(
            controller: _comment,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Votre avis (facultatif)',
              hintText: "Comment s'est passé le business ?",
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const Gap(8),
          FilledButton(
            onPressed: (_stars < 1 || _submitting) ? null : _submit,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(isEdit ? 'Mettre à jour' : 'Publier'),
          ),
        ],
      ),
    );
  }
}
