import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/providers/mcp_provider.dart';

void main() {
  group('McpProvider built-ins', () {
    test('adds fetch, files, github, and images built-in servers', () async {
      SharedPreferences.setMockInitialValues(const {});

      final provider = McpProvider();
      addTearDown(provider.dispose);
      await Future<void>.delayed(Duration.zero);

      final byId = {for (final server in provider.servers) server.id: server};

      expect(
        byId.keys,
        containsAll([
          'kelivo_fetch',
          'kelivo_files',
          'kelivo_github',
          'kelivo_images',
        ]),
      );
      expect(byId['kelivo_fetch']!.name, '@kelivo/fetch');
      expect(byId['kelivo_files']!.name, '@kelivo/files');
      expect(byId['kelivo_github']!.name, '@kelivo/github');
      expect(byId['kelivo_images']!.name, '@kelivo/images');
      expect(byId['kelivo_fetch']!.enabled, isTrue);
      expect(byId['kelivo_files']!.enabled, isFalse);
      expect(byId['kelivo_github']!.enabled, isFalse);
      expect(byId['kelivo_images']!.enabled, isFalse);
    });

    test('preserves images built-in through UI JSON import', () async {
      SharedPreferences.setMockInitialValues(const {});

      final provider = McpProvider();
      addTearDown(provider.dispose);
      await Future<void>.delayed(Duration.zero);

      await provider.replaceAllFromJson('''
{
  "mcpServers": {
    "kelivo_fetch": {"name": "@kelivo/fetch", "type": "inmemory", "isActive": false},
    "kelivo_files": {"name": "@kelivo/files", "type": "inmemory", "isActive": false},
    "kelivo_images": {"name": "@kelivo/images", "type": "inmemory", "isActive": true}
  }
}
''');

      final images = provider.getById('kelivo_images');
      expect(images, isNotNull);
      expect(images!.name, '@kelivo/images');
      expect(images.enabled, isTrue);
      expect(images.transport, McpTransportType.inmemory);
    });

    test('preserves github built-in through UI JSON import', () async {
      SharedPreferences.setMockInitialValues(const {});

      final provider = McpProvider();
      addTearDown(provider.dispose);
      await Future<void>.delayed(Duration.zero);

      await provider.replaceAllFromJson('''
{
  "mcpServers": {
    "kelivo_fetch": {"name": "@kelivo/fetch", "type": "inmemory", "isActive": false},
    "kelivo_github": {"name": "@kelivo/github", "type": "inmemory", "isActive": true}
  }
}
''');

      final github = provider.getById('kelivo_github');
      expect(github, isNotNull);
      expect(github!.name, '@kelivo/github');
      expect(github.enabled, isTrue);
      expect(github.transport, McpTransportType.inmemory);
    });

    test('persists github token configuration', () async {
      SharedPreferences.setMockInitialValues(const {});

      final provider = McpProvider();
      addTearDown(provider.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(provider.hasGithubToken, isFalse);

      await provider.updateGithubToken('  github_pat_test  ');

      expect(provider.hasGithubToken, isTrue);
      expect(provider.githubToken, 'github_pat_test');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mcp_github_token_v1'), 'github_pat_test');

      await provider.updateGithubToken('');

      expect(provider.hasGithubToken, isFalse);
      expect(prefs.containsKey('mcp_github_token_v1'), isFalse);
    });

    test('persists images API configuration', () async {
      SharedPreferences.setMockInitialValues(const {});

      final provider = McpProvider();
      addTearDown(provider.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(provider.hasImagesConfig, isFalse);
      expect(provider.imagesApiBaseUrl, 'https://api.openai.com/v1');

      await provider.updateImagesConfig(
        apiBaseUrl: '  https://images.example.com/v1  ',
        apiKey: '  image-secret  ',
      );

      expect(provider.hasImagesConfig, isTrue);
      expect(provider.imagesApiBaseUrl, 'https://images.example.com/v1');
      expect(provider.imagesApiKey, 'image-secret');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('mcp_images_api_base_url_v1'),
        'https://images.example.com/v1',
      );
      expect(prefs.getString('mcp_images_api_key_v1'), 'image-secret');

      await provider.updateImagesConfig(apiBaseUrl: '', apiKey: '');

      expect(provider.hasImagesConfig, isFalse);
      expect(provider.imagesApiBaseUrl, 'https://api.openai.com/v1');
      expect(
        prefs.getString('mcp_images_api_base_url_v1'),
        'https://api.openai.com/v1',
      );
      expect(prefs.containsKey('mcp_images_api_key_v1'), isFalse);
    });

    test('auto-connects enabled images built-in on load', () async {
      SharedPreferences.setMockInitialValues({
        'mcp_servers_v1': '''
[
  {"id":"kelivo_images","enabled":true,"name":"@kelivo/images","transport":"inmemory","tools":[]}
]
''',
      });

      final provider = McpProvider();
      addTearDown(provider.dispose);

      await _pumpUntil(() => provider.isConnected('kelivo_images'));

      expect(provider.isConnected('kelivo_images'), isTrue);
      expect(provider.getById('kelivo_images')!.tools, isNotEmpty);
    });

    test('marks grouped github write tools as requiring approval', () async {
      SharedPreferences.setMockInitialValues(const {});

      final provider = McpProvider();
      addTearDown(provider.dispose);
      await Future<void>.delayed(Duration.zero);

      await provider.connect('kelivo_github');

      final github = provider.getById('kelivo_github')!;
      final byName = {for (final tool in github.tools) tool.name: tool};

      expect(byName['github_search']!.needsApproval, isFalse);
      expect(byName['github_repository_write']!.needsApproval, isTrue);
      expect(byName['github_pull_request_write']!.needsApproval, isTrue);
      expect(byName['github_release_write']!.needsApproval, isTrue);
      expect(byName['github_actions_write']!.needsApproval, isTrue);
      expect(byName['github_secrets_write']!.needsApproval, isTrue);
    });
  });
}

Future<void> _pumpUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
