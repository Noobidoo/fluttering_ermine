import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/login_notifier.dart';
import '../../../models/permissions.dart';
import 'current_user_id_provider.dart';
import 'server_notifier.dart';

final effectivePermissionsProvider = Provider.family<int, String>((ref, serverId) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return 0;

  final serverState = ref.watch(serverStateProvider).asData?.value;
  if (serverState == null) return 0;

  final server = serverState.servers.firstWhere(
    (s) => s.id == serverId,
    orElse: () => serverState.servers.first,
  );
  if (server.id != serverId) return 0;

  final auth = ref.watch(loginStateProvider).asData?.value;
  if (auth == null) return 0;
  final user = auth.currentUser;
  if (user == null) return 0;
  if (user.privileged) return Permission.grantAllSafe;

  if (server.ownerId == userId) return Permission.grantAllSafe;

  final userRoleIds = user.serverProfiles[serverId]?.roles ?? [];
  return serverState.userEffectivePermissions(serverId, userRoleIds);
});
