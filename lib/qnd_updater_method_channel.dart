import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'qnd_updater_platform_interface.dart';

/// An implementation of [QndUpdaterPlatform] that uses method channels.
class MethodChannelQndUpdater extends QndUpdaterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('qnd_updater');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
