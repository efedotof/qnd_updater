import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qnd_updater/qnd_updater.dart';

const String kDemoBuildTag = 'build-003';

const List<String> kDemoChangelog = [
  'Initial release',
];

class UpdateTestScreen extends StatefulWidget {
  final String owner;
  final String repo;
  final String? githubToken;

  const UpdateTestScreen({
    super.key,
    required this.owner,
    required this.repo,
    this.githubToken,
  });

  @override
  State<UpdateTestScreen> createState() => _UpdateTestScreenState();
}

class _UpdateTestScreenState extends State<UpdateTestScreen> {
  final QndUpdater _updater = QndUpdater();
  late final UpdaterService _service = UpdaterService(
    owner: widget.owner,
    repo: widget.repo,
    githubToken: widget.githubToken,
  );

  String _status = 'idle';
  String _currentVersion = '...';
  String _remoteVersion = '...';
  UpdateStatus? _lastStatus;
  double _progress = 0;
  String _progressLabel = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
  }

  Future<void> _loadCurrentVersion() async {
    final v = await _updater.getAppVersion();
    debugPrint('qnd_updater: current=$v tag=$kDemoBuildTag');
    if (!mounted) return;
    setState(() => _currentVersion = v ?? 'unknown');
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _status = 'checking...';
      _progress = 0;
      _progressLabel = '';
      _lastStatus = null;
    });

    final status = await _updater.checkForUpdate(
      githubToken: widget.githubToken ?? '',
      owner: widget.owner,
      repo: widget.repo,
    );

    String remote = '?';
    try {
      final release = await _service.fetchLatestRelease();
      remote = release?.tag ?? '?';
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastStatus = status;
      _remoteVersion = remote;
      _status = switch (status) {
        UpdateStatus.upToDate => 'already up to date',
        UpdateStatus.updateAvailable => 'update available',
        UpdateStatus.error => 'error',
      };
    });
  }

  Future<void> _downloadAndApply() async {
    setState(() {
      _busy = true;
      _status = 'downloading...';
      _progress = 0;
      _progressLabel = '';
    });

    try {
      final platformKey = _platformKey();

      final result = await _service.downloadLatest(
        platformKey: platformKey,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _progress = total > 0 ? done / total : 0;
            final doneMb = (done / 1024 / 1024).toStringAsFixed(1);
            final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
            _progressLabel = '$doneMb / $totalMb MB';
          });
        },
      );

      if (result == null) {
        if (!mounted) return;
        setState(() {
          _status = 'no asset for platform "$platformKey"';
          _busy = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _status = 'applying ${result.version}...';
        _progressLabel = result.stagingDir.path;
      });

      await _updater.applyUpdate(result.stagingDir.path);

      if (Platform.isAndroid) {
        if (!mounted) return;
        setState(() {
          _status = 'system installer opened';
          _busy = false;
        });
      } else {
        await Future.delayed(const Duration(milliseconds: 500));
        exit(0);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'failed: $e';
        _busy = false;
      });
    }
  }

  String _platformKey() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'android';
  }

  @override
  Widget build(BuildContext context) {
    final canApply = _lastStatus == UpdateStatus.updateAvailable && !_busy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('qnd_updater test'),
        actions: [
          IconButton(
            tooltip: 'Reload version',
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : _loadCurrentVersion,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              _buildDemoBanner(context),
              const SizedBox(height: 20),
              _row('Repo', '${widget.owner}/${widget.repo}'),
              _row('Platform', Platform.operatingSystem),
              _row('Current version', _currentVersion),
              _row('Remote version', _remoteVersion),
              _row('Status', _status),
              const SizedBox(height: 20),
              if (_progress > 0) _buildProgress(context),
              FilledButton.icon(
                onPressed: _busy ? null : _check,
                icon: const Icon(Icons.search),
                label: const Text('1. Check for update'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: canApply ? _downloadAndApply : null,
                icon: const Icon(Icons.download),
                label: const Text('2. Download and apply'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDemoBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepPurple, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BUILD TAG',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.2,
              color: Colors.deepPurple.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            kDemoBuildTag,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Colors.deepPurple.shade900,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Changelog:',
            style: TextStyle(
              fontSize: 12,
              color: Colors.deepPurple.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          ...kDemoChangelog.map(
            (line) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('• $line'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: _progress),
        const SizedBox(height: 4),
        Text(
          _progressLabel,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
