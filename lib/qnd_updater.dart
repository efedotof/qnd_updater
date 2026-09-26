import 'package:flutter/foundation.dart';
import 'package:qnd_updater/src/get_last_version_repository_github.dart';

import 'qnd_updater_platform_interface.dart';

export 'src/models/update_manifest.dart';
export 'src/updater_service.dart';

enum UpdateStatus { upToDate, updateAvailable, error }

class QndUpdater {
  Future<String?> getAppVersion() =>
      QndUpdaterPlatform.instance.getAppVersion();

  Future<UpdateStatus> checkForUpdate({
    required String githubToken,
    required String owner,
    required String repo,
  }) async {
    final appVersion = await getAppVersion();
    if (appVersion == null) {
      debugPrint('Не удалось получить версию приложения');
      return UpdateStatus.error;
    }

    final last = await GetLastVersionRepositoryGithub(
      githubToken,
      owner: owner,
      repo: repo,
    ).getLastVersion();

    if (last == null) {
      debugPrint('Не удалось получить последнюю версию с GitHub');
      return UpdateStatus.error;
    }

    final cmp = _compareVersions(last, appVersion);
    debugPrint('local=$appVersion remote=$last cmp=$cmp');

    return cmp > 0 ? UpdateStatus.updateAvailable : UpdateStatus.upToDate;
  }

  Future<bool> applyUpdate(String path) =>
      QndUpdaterPlatform.instance.applyUpdate(path);

  int _compareVersions(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y ? 1 : -1;
    }
    return 0;
  }
}
