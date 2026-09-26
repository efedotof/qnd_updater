import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qnd_updater/qnd_updater.dart';
void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: HomePage());
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _status = 'idle';
  double _progress = 0;

  Future<void> _check() async {
    setState(() => _status = 'checking...');

    final updater = QndUpdater();
    final status = await updater.checkForUpdate(
      githubToken: '...', 
      owner: 'efedotof',
      repo: 'qnd_updater',
    );

    setState(() => _status = status.name);
    if (status != UpdateStatus.updateAvailable) return;

    final platformKey = Platform.isWindows
        ? 'windows'
        : Platform.isMacOS
            ? 'macos'
            : 'android';

    final svc = UpdaterService(owner: 'efedotof', repo: 'qnd_updater');

    if (Platform.isWindows || Platform.isMacOS) {
      final appDir = File(Platform.resolvedExecutable).parent;
      final plan = await svc.planUpdate(appDir: appDir, platformKey: platformKey);
      if (plan == null) {
        setState(() => _status = 'no manifest');
        return;
      }
      setState(() => _status =
          'download ${plan.changed.length} files (${plan.bytesToDownload} B)');

      final release = await svc.fetchLatestRelease();
      final tmp = await getTemporaryDirectory();
      final staging = Directory('${tmp.path}/qnd_staging');

      await svc.downloadChanged(
        plan: plan,
        release: release!,
        stagingDir: staging,
        onProgress: (done, total) {
          if (total > 0) {
            setState(() => _progress = done / total);
          }
        },
      );

      setState(() => _status = 'applying...');
      await updater.applyUpdate(staging.path);
      await Future.delayed(const Duration(milliseconds: 300));
      exit(0);
    } else {
      final release = await svc.fetchLatestRelease();
      final apkAsset =
          release!.assets['qnd_updater-${release.tag}.apk'];
      if (apkAsset == null) {
        setState(() => _status = 'APK asset not found');
        return;
      }
      final tmp = await getTemporaryDirectory();
      final apkFile = File('${tmp.path}/update.apk');
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(apkAsset.browserDownloadUrl));
      final resp = await req.close();
      final sink = apkFile.openWrite();
      await resp.pipe(sink);
      await sink.close();
      client.close();

      setState(() => _status = 'installing...');
      await updater.applyUpdate(apkFile.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('qnd_updater example')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('status: $_status'),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _check, child: const Text('Проверить')),
          ],
        ),
      ),
    );
  }
}