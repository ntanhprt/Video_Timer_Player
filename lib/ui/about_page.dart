import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/changelog.dart';

/// "version (build)" of the installed app, e.g. "0.3.0 (build 12)".
Future<String> appVersionLabel() async {
  try {
    final i = await PackageInfo.fromPlatform();
    return '${i.version} (build ${i.buildNumber})';
  } catch (_) {
    return changelog.first.version;
  }
}

/// Small tappable version text for the list screen.
class VersionLabel extends StatelessWidget {
  const VersionLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: appVersionLabel(),
      builder: (context, snap) => TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutPage())),
        child: Text('Phiên bản ${snap.data ?? changelog.first.version} • Có gì mới'),
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Phiên bản & có gì mới')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FutureBuilder<String>(
            future: appVersionLabel(),
            builder: (_, snap) => Text('Đang cài: ${snap.data ?? '...'}', style: text.titleLarge),
          ),
          const SizedBox(height: 16),
          for (final e in changelog) ...[
            Text('${e.version} — ${e.date}', style: text.titleMedium),
            const SizedBox(height: 4),
            for (final c in e.changes)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Text('• $c'),
              ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}
