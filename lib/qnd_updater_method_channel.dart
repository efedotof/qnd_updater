import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'qnd_updater_platform_interface.dart';

class MethodChannelQndUpdater extends QndUpdaterPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('qnd_updater');

  @override
  Future<String?> getAppVersion() async {
    return methodChannel.invokeMethod<String>('getAppVersion');
  }

  @override
  Future<bool> applyUpdate(String stagingDir) async {
    final ok = await methodChannel.invokeMethod<bool>(
      'applyUpdate',
      <String, dynamic>{'stagingDir': stagingDir},
    );
    return ok ?? false;
  }
}
