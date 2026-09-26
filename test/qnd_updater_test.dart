// import 'package:flutter_test/flutter_test.dart';
// import 'package:qnd_updater/qnd_updater.dart';
// import 'package:qnd_updater/qnd_updater_platform_interface.dart';
// import 'package:qnd_updater/qnd_updater_method_channel.dart';
// import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// class MockQndUpdaterPlatform
//     with MockPlatformInterfaceMixin
//     implements QndUpdaterPlatform {

//   @override
//   Future<String?> getPlatformVersion() => Future.value('42');
// }

// void main() {
//   final QndUpdaterPlatform initialPlatform = QndUpdaterPlatform.instance;

//   test('$MethodChannelQndUpdater is the default instance', () {
//     expect(initialPlatform, isInstanceOf<MethodChannelQndUpdater>());
//   });

//   test('getPlatformVersion', () async {
//     QndUpdater qndUpdaterPlugin = QndUpdater();
//     MockQndUpdaterPlatform fakePlatform = MockQndUpdaterPlatform();
//     QndUpdaterPlatform.instance = fakePlatform;

//     expect(await qndUpdaterPlugin.getPlatformVersion(), '42');
//   });
// }
