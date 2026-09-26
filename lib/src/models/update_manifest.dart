class UpdateManifest {
  final String version;
  final String? minVersion;
  final Map<String, FileEntry> files;

  UpdateManifest({
    required this.version,
    this.minVersion,
    required this.files,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    final map = <String, FileEntry>{};
    for (final f in (json['files'] as List)) {
      final e = FileEntry.fromJson(f as Map<String, dynamic>);
      map[e.path] = e;
    }
    return UpdateManifest(
      version: json['version'] as String,
      minVersion: json['min_version'] as String?,
      files: map,
    );
  }
}

class FileEntry {
  final String path;    
  final String sha256;   
  final int size;
  final String asset;   

  FileEntry({
    required this.path,
    required this.sha256,
    required this.size,
    required this.asset,
  });

  factory FileEntry.fromJson(Map<String, dynamic> json) => FileEntry(
        path: json['path'] as String,
        sha256: json['sha256'] as String,
        size: json['size'] as int,
        asset: json['asset'] as String,
      );
}