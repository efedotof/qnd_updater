// You have generated a new plugin project without specifying the `--platforms`
// flag. A plugin project with no platform support was generated. To add a
// platform, run `flutter create -t plugin --platforms <platforms> .` under the
// same directory. You can also find a detailed instruction on how to add
// platforms in the `pubspec.yaml` at
// https://flutter.dev/docs/development/packages-and-plugins/developing-packages#plugin-platforms.

import 'package:flutter/material.dart';
import 'package:qnd_updater/src/get_last_version_repository_github.dart';

import 'qnd_updater_platform_interface.dart';

class QndUpdater {
  void getLastVersion(
      {required String githubToken,
      required String owner,
      required String repo}) async {
    final appVersion = await getAppVersion(); // get app Version

    GetLastVersionRepositoryGithub getLastVersion =
        GetLastVersionRepositoryGithub(githubToken, owner: owner, repo: repo);

    final res = await getLastVersion.getLastVersion();

    if (res == null && appVersion == null) {
      debugPrint("Проверте правильность ваших данных!!!");
    }

    final newVersion = _compareVersions(res!, appVersion!);

    if (newVersion == 1) {
      debugPrint("Доступна новая версия!!!");
    }
  }

  Future<String?> getAppVersion() {
    return QndUpdaterPlatform.instance.getAppVersion();
  }

  int _compareVersions(String versionA, String versionB) {
    final partsA = versionA.split('.').map(int.parse).toList();
    final partsB = versionB.split('.').map(int.parse).toList();

    for (var i = 0; i < partsA.length || i < partsB.length; i++) {
      final numA = i < partsA.length ? partsA[i] : 0;
      final numB = i < partsB.length ? partsB[i] : 0;

      if (numA != numB) {
        return numA > numB ? 1 : -1;
      }
    }

    return 0;
  }
}
