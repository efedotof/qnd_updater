import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'models/update_manifest.dart';

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

class UpdatePlan {
  final String version;
  final String tag;
  final List<FileEntry> changed;
  final int bytesToDownload;
  UpdatePlan({
    required this.version,
    required this.tag,
    required this.changed,
    required this.bytesToDownload,
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
    final url = Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest');
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

 
  Future<UpdatePlan?> planUpdate({
    required Directory appDir,
    required String platformKey, 
  }) async {
    final release = await fetchLatestRelease();
    if (release == null) return null;

    final manifestName = 'manifest-$platformKey.json';
    final manifestAsset = release.assets[manifestName];
    if (manifestAsset == null) {
      debugPrint('Нет ассета $manifestName в релизе ${release.tag}');
      return null;
    }

    final manifest = await _downloadManifest(manifestAsset);
    final changed = <FileEntry>[];
    int bytes = 0;

    for (final entry in manifest.files.values) {
      final local = File(p.join(appDir.path, entry.path));
      if (!await local.exists()) {
        changed.add(entry);
        bytes += entry.size;
        continue;
      }
      final localHash = await _sha256File(local);
      if (localHash != entry.sha256) {
        changed.add(entry);
        bytes += entry.size;
      }
    }

    return UpdatePlan(
      version: manifest.version,
      tag: release.tag,
      changed: changed,
      bytesToDownload: bytes,
    );
  }

  Future<Directory> downloadChanged({
    required UpdatePlan plan,
    required GithubRelease release,
    required Directory stagingDir,
    void Function(int downloaded, int total)? onProgress,
  }) async {
    if (await stagingDir.exists()) await stagingDir.delete(recursive: true);
    await stagingDir.create(recursive: true);

    int done = 0;
    final total = plan.bytesToDownload;

    for (final entry in plan.changed) {
      final asset = release.assets[entry.asset];
      if (asset == null) {
        throw StateError('Ассет ${entry.asset} отсутствует в релизе');
      }
      final dst = File(p.join(stagingDir.path, entry.path));
      await dst.parent.create(recursive: true);

      final req = http.Request('GET', Uri.parse(asset.browserDownloadUrl));
      req.headers.addAll(_headers);
      req.headers['Accept'] = 'application/octet-stream';
      final resp = await _client.send(req);
      if (resp.statusCode != 200) {
        throw StateError('Скачивание ${entry.asset}: HTTP ${resp.statusCode}');
      }
      final sink = dst.openWrite();
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        done += chunk.length;
        onProgress?.call(done, total);
      }
      await sink.close();

      final got = await _sha256File(dst);
      if (got != entry.sha256) {
        throw StateError('Хэш ${entry.path} не совпал: $got != ${entry.sha256}');
      }
    }
    return stagingDir;
  }

  Future<UpdateManifest> _downloadManifest(GithubAsset asset) async {
    final req = http.Request('GET', Uri.parse(asset.browserDownloadUrl));
    req.headers.addAll(_headers);
    req.headers['Accept'] = 'application/octet-stream';
    final resp = await _client.send(req);
    final body = await resp.stream.bytesToString();
    return UpdateManifest.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  static Future<String> _sha256File(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}