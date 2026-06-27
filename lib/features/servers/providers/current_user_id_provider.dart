import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/login_notifier.dart';

/// Derived provider that reactively extracts [currentUserId] from the new
/// [LoginNotifier] without imperative setters (Rule 3: Pull, Don't Push).
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(loginStateProvider).asData?.value.currentUser?.id;
});
