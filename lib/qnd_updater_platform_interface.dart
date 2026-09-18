import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'qnd_updater_method_channel.dart';

abstract class QndUpdaterPlatform extends PlatformInterface {
  /// Constructs a QndUpdaterPlatform.
  QndUpdaterPlatform() : super(token: _token);

  static final Object _token = Object();

  static QndUpdaterPlatform _instance = MethodChannelQndUpdater();

  /// The default instance of [QndUpdaterPlatform] to use.
  ///
  /// Defaults to [MethodChannelQndUpdater].
  static QndUpdaterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [QndUpdaterPlatform] when
  /// they register themselves.
  static set instance(QndUpdaterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getAppVersion() {
    throw UnimplementedError('getAppVersion() has not been implemented.');
  }
}
