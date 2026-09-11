import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/features/added_events/domain/added_by_user.dart';

/// The people who added the caller to their contacts (cahier §21), newest
/// first. Loaded once on build; pull-to-refresh invalidates the provider.
class WhoAddedMeController extends AsyncNotifier<List<AddedByUser>> {
  @override
  FutureOr<List<AddedByUser>> build() async {
    final result = await ref.watch(addedEventsRepositoryProvider).whoAddedMe();
    return result.items;
  }
}

final whoAddedMeControllerProvider =
    AsyncNotifierProvider<WhoAddedMeController, List<AddedByUser>>(
  WhoAddedMeController.new,
);
