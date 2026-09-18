import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class GetLastVersionRepositoryGithub {
  final String? githubToken;
  final String owner;
  final String repo;

  GetLastVersionRepositoryGithub(
    this.githubToken, {
    required this.owner,
    required this.repo,
  });

  static const String _baseUrl = 'https://api.github.com';

  Future<String?> getLastVersion() async {
    try {
      final url = Uri.parse('$_baseUrl/repos/$owner/$repo/releases/latest');
      final response = await http.get(url, headers: _headers());

      if (response.statusCode != 200) {
        debugPrint('GitHub вернул ${response.statusCode}: ${response.body}');
        return null;
      }

      final Map<String, dynamic> jsonData =
          jsonDecode(response.body) as Map<String, dynamic>;

      final tag = jsonData['tag_name'] as String?;
      if (tag == null) return null;
      return tag.startsWith('v') ? tag.substring(1) : tag;
    } catch (e) {
      debugPrint('Ошибка получения версии: $e');
      return null;
    }
  }

  Map<String, String> _headers() {
    final headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2026-03-10',
    };
    if (githubToken != null && githubToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $githubToken';
    }
    return headers;
  }
}
