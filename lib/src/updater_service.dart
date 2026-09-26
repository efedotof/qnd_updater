import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class GithubRelease {
  final String tag;
  final String name;
  final Map<String, GithubAsset> assets;

  GithubRelease({required this.tag, required this.name, required this.assets});
}

class GithubAsset {
  final int id;
  final String name;
  final int size;
  final String browserDownloadUrl;

  GithubAsset({
    required this.id,
    required this.name,
    required this.size,
    required this.browserDownloadUrl,
  });
}

class UpdateResult {
  final String version;
  final String tag;
  final Directory stagingDir;
  final int totalBytes;

  UpdateResult({
    required this.version,
    required this.tag,
    required this.stagingDir,
    required this.totalBytes,
  });
}

class UpdaterService {
  final String owner;
  final String repo;
  final String? githubToken;
  final http.Client _client;

  UpdaterService({
    required this.owner,
    required this.repo,
    this.githubToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Map<String, String> get _headers => {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2026-03-10',
        if (githubToken != null && githubToken!.isNotEmpty)
          'Authorization': 'Bearer $githubToken',
      };

  Future<GithubRelease?> fetchLatestRelease() async {
    final url =
        Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest');
    final resp = await _client.get(url, headers: _headers);
    if (resp.statusCode != 200) {
      debugPrint('GitHub releases: ${resp.statusCode} ${resp.body}');
      return null;
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final assets = <String, GithubAsset>{};
    for (final a in (json['assets'] as List)) {
      final m = a as Map<String, dynamic>;
      final asset = GithubAsset(
        id: m['id'] as int,
        name: m['name'] as String,
        size: m['size'] as int,
        browserDownloadUrl: m['browser_download_url'] as String,
      );
      assets[asset.name] = asset;
    }
    return GithubRelease(
      tag: json['tag_name'] as String,
      name: (json['name'] as String?) ?? json['tag_name'] as String,
      assets: assets,
    );
  }

  String _assetNameFor(String platformKey, String tag) {
    final cleanTag = tag.startsWith('v') ? tag : 'v$tag';
    return 'qnd_updater-$cleanTag-$platformKey.zip';
  }

  Future<UpdateResult?> downloadUpdate({
    required String platformKey,
    required Directory stagingDir,
    void Function(int downloaded, int total)? onProgress,
  }) async {
    final release = await fetchLatestRelease();
    if (release == null) return null;

    final assetName = _assetNameFor(platformKey, release.tag);
    final asset = release.assets[assetName];
    if (asset == null) {
      debugPrint('Ассет "$assetName" не найден. Доступные: '
          '${release.assets.keys.join(", ")}');
      return null;
    }

    if (await stagingDir.exists()) {
      await stagingDir.delete(recursive: true);
    }
    await stagingDir.create(recursive: true);

    final zipFile = File('${stagingDir.path}/_update.zip');

    final req = http.Request('GET', Uri.parse(asset.browserDownloadUrl));
    req.headers.addAll(_headers);
    req.headers['Accept'] = 'application/octet-stream';
    final resp = await _client.send(req);
    if (resp.statusCode != 200) {
      throw StateError('Скачивание ${asset.name}: HTTP ${resp.statusCode}');
    }

    final cl = resp.contentLength;
    final int total = (cl != null && cl > 0) ? cl : asset.size;

    int done = 0;
    final sink = zipFile.openWrite();
    await for (final chunk in resp.stream) {
      sink.add(chunk);
      done += chunk.length;
      onProgress?.call(done, total);
    }
    await sink.close();
    if (Platform.isMacOS) {
      final ditto = await Process.run(
        '/usr/bin/ditto',
        ['-x', '-k', zipFile.path, stagingDir.path],
      );
      if (ditto.exitCode != 0) {
        throw StateError(
          'ditto failed (${ditto.exitCode}): ${ditto.stderr}',
        );
      }
      await _verifyStagedApp(stagingDir);
    } else {
      final input = InputFileStream(zipFile.path);
      final archive = ZipDecoder().decodeStream(input);
      for (final file in archive) {
        final outPath = '${stagingDir.path}/${file.name}';
        if (file.isFile) {
          final out = File(outPath);
          await out.parent.create(recursive: true);
          await out.writeAsBytes(file.content as List<int>, flush: true);
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }
      await input.close();
    }
    await zipFile.delete();

    final version =
        release.tag.startsWith('v') ? release.tag.substring(1) : release.tag;

    return UpdateResult(
      version: version,
      tag: release.tag,
      stagingDir: stagingDir,
      totalBytes: done,
    );
  }

  Future<void> _verifyStagedApp(Directory stagingDir) async {
    final appDirs = stagingDir
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.endsWith('.app'))
        .toList();

    if (appDirs.isEmpty) {
      throw StateError('В staging нет ни одного .app: ${stagingDir.path}');
    }

    for (final app in appDirs) {
      final appFramework =
          Link('${app.path}/Contents/Frameworks/App.framework/App');
      final appResources =
          Link('${app.path}/Contents/Frameworks/App.framework/Resources');

      if (!appFramework.existsSync()) {
        throw StateError(
          'App.framework/App не симлинк — распаковка сломала бандл: '
          '$appFramework',
        );
      }
      if (!appResources.existsSync()) {
        throw StateError(
          'App.framework/Resources не симлинк: $appResources',
        );
      }

      final flutterAssets = Directory(
        '${app.path}/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets',
      );
      if (!flutterAssets.existsSync()) {
        throw StateError('flutter_assets не найден: $flutterAssets');
      }

      final icudtl = File(
        '${app.path}/Contents/Frameworks/FlutterMacOS.framework/Versions/A/Resources/icudtl.dat',
      );
      if (!icudtl.existsSync()) {
        throw StateError('icudtl.dat не найден: $icudtl');
      }

      final macosDir = Directory('${app.path}/Contents/MacOS');
      if (!macosDir.existsSync()) {
        throw StateError('Contents/MacOS отсутствует: $macosDir');
      }
      for (final entity in macosDir.listSync()) {
        if (entity is File) {
          final mode = entity.statSync().mode;
          if ((mode & 0x40) == 0) {
            throw StateError(
              'Бинарник без +x: ${entity.path} (mode=${mode.toRadixString(8)})',
            );
          }
        }
      }
    }
  }

  Future<UpdateResult?> downloadLatest({
    required String platformKey,
    void Function(int downloaded, int total)? onProgress,
  }) async {
    final tmp = await getTemporaryDirectory();
    final staging = Directory('${tmp.path}/qnd_staging');
    return downloadUpdate(
      platformKey: platformKey,
      stagingDir: staging,
      onProgress: onProgress,
    );
  }
}
