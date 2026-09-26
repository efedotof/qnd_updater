import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'qnd_updater_method_channel.dart';

abstract class QndUpdaterPlatform extends PlatformInterface {
  QndUpdaterPlatform() : super(token: _token);

  static final Object _token = Object();
  static QndUpdaterPlatform _instance = MethodChannelQndUpdater();

  static QndUpdaterPlatform get instance => _instance;

  static set instance(QndUpdaterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getAppVersion() {
    throw UnimplementedError('getAppVersion() has not been implemented.');
  }

  Future<bool> applyUpdate(String stagingOrApkPath) {
    throw UnimplementedError('applyUpdate() has not been implemented.');
  }
}