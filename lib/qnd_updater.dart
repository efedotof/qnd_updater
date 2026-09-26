import 'package:flutter/foundation.dart';
import 'package:qnd_updater/src/get_last_version_repository_github.dart';

import 'qnd_updater_platform_interface.dart';

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
    debugPrint('local="$appVersion" remote="$last" cmp=$cmp');

    if (cmp < 0) return UpdateStatus.error;
    return cmp > 0 ? UpdateStatus.updateAvailable : UpdateStatus.upToDate;
  }

  Future<bool> applyUpdate(String path) =>
      QndUpdaterPlatform.instance.applyUpdate(path);

  static String _normalize(String v) {
    var s = v.trim();
    if (s.startsWith('v')) s = s.substring(1);
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);
    return s;
  }

  int _compareVersions(String a, String b) {
    final na = _normalize(a);
    final nb = _normalize(b);

    final partsA = na.split('.');
    final partsB = nb.split('.');

    final pa = <int>[];
    for (final p in partsA) {
      final n = int.tryParse(p);
      if (n == null) return 0;
      pa.add(n);
    }
    final pb = <int>[];
    for (final p in partsB) {
      final n = int.tryParse(p);
      if (n == null) return 0;
      pb.add(n);
    }

    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y ? 1 : -1;
    }
    return 0;
  }
}
