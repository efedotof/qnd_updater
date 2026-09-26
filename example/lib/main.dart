import 'package:flutter/material.dart';

import 'test.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'qnd_updater test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: const UpdateTestScreen(
        owner: 'efedotof',
        repo: 'qnd_updater',
        // githubToken: 'ghp_xxx', //  если репозиторий приватный
      ),
    );
  }
}
