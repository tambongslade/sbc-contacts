import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/features/directory/domain/member.dart';

class FavoritesController extends AsyncNotifier<List<Member>> {
  @override
  FutureOr<List<Member>> build() async {
    final result = await ref.watch(favoritesRepositoryProvider).list();
    return result.items;
  }

  Future<void> add(String memberSbcId) async {
    await ref.read(favoritesRepositoryProvider).add(memberSbcId);
    ref.invalidateSelf();
  }

  Future<void> remove(String memberSbcId) async {
    // optimistic removal
    final current = state.value ?? [];
    state = AsyncValue.data(current.where((m) => m.sbcId != memberSbcId).toList());
    await ref.read(favoritesRepositoryProvider).remove(memberSbcId);
  }
}

final favoritesControllerProvider =
    AsyncNotifierProvider<FavoritesController, List<Member>>(FavoritesController.new);
