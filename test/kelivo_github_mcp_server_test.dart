import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/mcp/kelivo_github/github_api_client.dart';
import 'package:Kelivo/core/services/mcp/kelivo_github/kelivo_github_server.dart';

void main() {
  group('GitHubApiClient', () {
    test('searches code with token auth and compact result shape', () async {
      final requests = <HttpRequest>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        requests.add(request);
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'total_count': 1,
            'incomplete_results': false,
            'items': [
              {
                'name': 'mcp_provider.dart',
                'path': 'lib/core/providers/mcp_provider.dart',
                'sha': 'abc123',
                'html_url': 'https://github.com/acme/app/blob/main/file.dart',
                'score': 12.3,
                'repository': {
                  'full_name': 'acme/app',
                  'html_url': 'https://github.com/acme/app',
                  'default_branch': 'main',
                  'private': false,
                },
              },
            ],
          }),
        );
        await request.response.close();
      });

      final client = GitHubApiClient(
        baseUri: Uri.parse('http://${server.address.address}:${server.port}'),
        accessTokenProvider: () async => 'github-token',
      );
      addTearDown(client.close);

      final result = await client.searchCode(
        query: 'McpProvider repo:acme/app language:Dart',
        perPage: 5,
      );

      expect(result['total_count'], 1);
      expect(result['items'], hasLength(1));
      expect(
        result['items'][0]['path'],
        'lib/core/providers/mcp_provider.dart',
      );
      expect(requests.single.uri.path, '/search/code');
      expect(
        requests.single.uri.queryParameters['q'],
        'McpProvider repo:acme/app language:Dart',
      );
      expect(requests.single.uri.queryParameters['per_page'], '5');
      expect(
        requests.single.headers.value(HttpHeaders.authorizationHeader),
        'Bearer github-token',
      );
      expect(
        requests.single.headers.value('X-GitHub-Api-Version'),
        '2022-11-28',
      );
    });

    test('decodes repository file content with bounded paging', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'type': 'file',
            'name': 'README.md',
            'path': 'README.md',
            'sha': 'abc123',
            'size': 11,
            'html_url': 'https://github.com/acme/app/blob/main/README.md',
            'download_url':
                'https://raw.githubusercontent.com/acme/app/main/README.md',
            'encoding': 'base64',
            'content': base64Encode(utf8.encode('hello world')),
          }),
        );
        await request.response.close();
      });

      final client = GitHubApiClient(
        baseUri: Uri.parse('http://${server.address.address}:${server.port}'),
      );
      addTearDown(client.close);

      final result = await client.getFile(
        owner: 'acme',
        repo: 'app',
        path: 'README.md',
        maxLength: 5,
      );

      expect(result['content'], 'hello');
      expect(result['truncated'], isTrue);
      expect(result['next_start_index'], 5);
      expect(result['total_characters'], 11);
    });

    test('throws useful exception for GitHub API errors', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        request.response.statusCode = HttpStatus.forbidden;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'message': 'Resource not accessible by personal access token',
            'documentation_url': 'https://docs.github.com/rest',
          }),
        );
        await request.response.close();
      });

      final client = GitHubApiClient(
        baseUri: Uri.parse('http://${server.address.address}:${server.port}'),
      );
      addTearDown(client.close);

      expect(
        () => client.searchRepositories(query: 'flutter'),
        throwsA(
          isA<GitHubApiException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.message, 'message', contains('not accessible')),
        ),
      );
    });

    test('creates or updates file with commit body and token auth', () async {
      final requests = <HttpRequest>[];
      final bodies = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        requests.add(request);
        bodies.add(await utf8.decoder.bind(request).join());
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'content': {
              'name': 'README.md',
              'path': 'README.md',
              'sha': 'new-sha',
              'html_url': 'https://github.com/acme/app/blob/main/README.md',
            },
            'commit': {
              'sha': 'commit-sha',
              'html_url': 'https://github.com/acme/app/commit/commit-sha',
              'message': 'docs: update readme',
            },
          }),
        );
        await request.response.close();
      });

      final client = GitHubApiClient(
        baseUri: Uri.parse('http://${server.address.address}:${server.port}'),
        accessTokenProvider: () async => 'write-token',
      );
      addTearDown(client.close);

      final result = await client.createOrUpdateFile(
        owner: 'acme',
        repo: 'app',
        path: 'README.md',
        content: 'hello',
        message: 'docs: update readme',
        branch: 'feature/docs',
        sha: 'old-sha',
      );

      expect(requests.single.method, 'PUT');
      expect(requests.single.uri.path, '/repos/acme/app/contents/README.md');
      expect(
        requests.single.headers.value(HttpHeaders.authorizationHeader),
        'Bearer write-token',
      );
      final body = jsonDecode(bodies.single) as Map<String, dynamic>;
      expect(body['message'], 'docs: update readme');
      expect(body['branch'], 'feature/docs');
      expect(body['sha'], 'old-sha');
      expect(utf8.decode(base64Decode(body['content'] as String)), 'hello');
      expect(result['commit']['sha'], 'commit-sha');
    });

    test('creates issue comment', () async {
      final requests = <HttpRequest>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        requests.add(request);
        await utf8.decoder.bind(request).join();
        request.response.statusCode = HttpStatus.created;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'id': 10,
            'user': {'login': 'octo'},
            'html_url': 'https://github.com/acme/app/issues/7#issuecomment-10',
            'created_at': '2026-07-26T00:00:00Z',
            'updated_at': '2026-07-26T00:00:00Z',
            'body': 'Looks good',
          }),
        );
        await request.response.close();
      });

      final client = GitHubApiClient(
        baseUri: Uri.parse('http://${server.address.address}:${server.port}'),
      );
      addTearDown(client.close);

      final result = await client.createIssueComment(
        owner: 'acme',
        repo: 'app',
        issueNumber: 7,
        body: 'Looks good',
      );

      expect(requests.single.method, 'POST');
      expect(requests.single.uri.path, '/repos/acme/app/issues/7/comments');
      expect(result['id'], 10);
      expect(result['body'], 'Looks good');
    });

    test('initializes empty repository before creating a branch', () async {
      final requests = <HttpRequest>[];
      final bodies = <Map<String, dynamic>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        requests.add(request);
        final bodyText = await utf8.decoder.bind(request).join();
        if (bodyText.isNotEmpty) {
          bodies.add(jsonDecode(bodyText) as Map<String, dynamic>);
        }
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'GET' &&
            request.uri.path == '/repos/acme/empty') {
          request.response.statusCode = HttpStatus.ok;
          request.response.write(jsonEncode({'default_branch': 'main'}));
        } else if (request.method == 'GET' &&
            request.uri.path == '/repos/acme/empty/git/ref/heads/main') {
          request.response.statusCode = HttpStatus.conflict;
          request.response.write(
            jsonEncode({'message': 'Git Repository is empty.'}),
          );
        } else if (request.method == 'PUT' &&
            request.uri.path == '/repos/acme/empty/contents/README.md') {
          request.response.statusCode = HttpStatus.created;
          request.response.write(
            jsonEncode({
              'content': {'path': 'README.md', 'sha': 'file-sha'},
              'commit': {
                'sha': 'init-sha',
                'html_url': 'https://github.com/acme/empty/commit/init-sha',
                'message': 'Initialize repository',
              },
            }),
          );
        } else if (request.method == 'POST' &&
            request.uri.path == '/repos/acme/empty/git/refs') {
          request.response.statusCode = HttpStatus.created;
          request.response.write(
            jsonEncode({
              'ref': 'refs/heads/feature/start',
              'url':
                  'https://api.github.com/repos/acme/empty/git/refs/heads/feature/start',
              'object': {
                'type': 'commit',
                'sha': 'init-sha',
                'url':
                    'https://api.github.com/repos/acme/empty/git/commits/init-sha',
              },
            }),
          );
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write(jsonEncode({'message': 'not found'}));
        }
        await request.response.close();
      });

      final client = GitHubApiClient(
        baseUri: Uri.parse('http://${server.address.address}:${server.port}'),
      );
      addTearDown(client.close);

      final result = await client.createBranch(
        owner: 'acme',
        repo: 'empty',
        branch: 'feature/start',
      );

      expect(result['initialized_repository'], isTrue);
      expect(result['object']['sha'], 'init-sha');
      expect(
        requests.map((r) => r.method),
        containsAll(['GET', 'PUT', 'POST']),
      );
      expect(bodies.last['ref'], 'refs/heads/feature/start');
      expect(bodies.last['sha'], 'init-sha');
    });

    test('rejects reserved GITHUB_ variable prefix before API call', () async {
      final client = GitHubApiClient(baseUri: Uri.parse('http://127.0.0.1:9'));
      addTearDown(client.close);

      expect(
        () => client.createOrUpdateRepositoryVariable(
          owner: 'acme',
          repo: 'app',
          name: 'GITHUB_TOKEN_ALIAS',
          value: 'x',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('GITHUB_'),
          ),
        ),
      );
    });

    test(
      'creates PR review comments with separate inline and reply payloads',
      () async {
        final bodies = <Map<String, dynamic>>[];
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await server.close(force: true);
        });

        server.listen((request) async {
          bodies.add(
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>,
          );
          request.response.statusCode = HttpStatus.created;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'id': bodies.length,
              'user': {'login': 'octo'},
              'body': bodies.last['body'],
              'path': bodies.last['path'],
              'line': bodies.last['line'],
              'side': bodies.last['side'],
              'commit_id': bodies.last['commit_id'],
              'in_reply_to_id': bodies.last['in_reply_to'],
              'html_url':
                  'https://github.com/acme/app/pull/3#discussion_r${bodies.length}',
              'created_at': '2026-07-26T00:00:00Z',
              'updated_at': '2026-07-26T00:00:00Z',
            }),
          );
          await request.response.close();
        });

        final client = GitHubApiClient(
          baseUri: Uri.parse('http://${server.address.address}:${server.port}'),
        );
        addTearDown(client.close);

        await client.createPullRequestReviewComment(
          owner: 'acme',
          repo: 'app',
          pullNumber: 3,
          body: 'Inline note',
          commitId: 'commit-sha',
          path: 'lib/app.dart',
          line: 12,
          side: 'RIGHT',
        );
        await client.createPullRequestReviewComment(
          owner: 'acme',
          repo: 'app',
          pullNumber: 3,
          body: 'Reply note',
          inReplyTo: 99,
        );

        expect(bodies.first, {
          'body': 'Inline note',
          'commit_id': 'commit-sha',
          'path': 'lib/app.dart',
          'line': 12,
          'side': 'RIGHT',
        });
        expect(bodies.last, {'body': 'Reply note', 'in_reply_to': 99});
      },
    );

    test(
      'ignores non-positive in_reply_to when creating new inline comments through MCP',
      () async {
        final bodies = <Map<String, dynamic>>[];
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await server.close(force: true);
        });

        server.listen((request) async {
          bodies.add(
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>,
          );
          request.response.statusCode = HttpStatus.created;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'id': bodies.length,
              'user': {'login': 'octo'},
              'body': bodies.last['body'],
              'path': bodies.last['path'],
              'line': bodies.last['line'],
              'side': bodies.last['side'],
              'commit_id': bodies.last['commit_id'],
              'html_url':
                  'https://github.com/acme/app/pull/3#discussion_r${bodies.length}',
              'created_at': '2026-07-26T00:00:00Z',
              'updated_at': '2026-07-26T00:00:00Z',
            }),
          );
          await request.response.close();
        });

        final engine = KelivoGithubMcpServerEngine(
          client: GitHubApiClient(
            baseUri: Uri.parse(
              'http://${server.address.address}:${server.port}',
            ),
          ),
        );
        addTearDown(engine.close);

        await engine.handleMessage({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/call',
          'params': {
            'name': 'github_pull_request_write',
            'arguments': {
              'action': 'create_review_comment',
              'owner': 'acme',
              'repo': 'app',
              'pull_number': 3,
              'body': 'Inline note',
              'commit_id': 'commit-sha',
              'path': 'lib/app.dart',
              'line': 12,
              'side': 'RIGHT',
              'in_reply_to': 0,
            },
          },
        });

        expect(bodies.single, {
          'body': 'Inline note',
          'commit_id': 'commit-sha',
          'path': 'lib/app.dart',
          'line': 12,
          'side': 'RIGHT',
        });
      },
    );
  });

  group('KelivoGithubMcpServerEngine', () {
    test(
      'lists grouped GitHub tools instead of one tool per endpoint',
      () async {
        final engine = KelivoGithubMcpServerEngine(
          client: GitHubApiClient(baseUri: Uri.parse('http://127.0.0.1:9')),
        );
        addTearDown(engine.close);

        final response =
            await engine.handleMessage({
                  'jsonrpc': '2.0',
                  'id': 1,
                  'method': 'tools/list',
                })
                as Map<String, dynamic>;

        final tools = response['result']['tools'] as List;
        final names = tools.map((tool) => tool['name']).toList();
        expect(
          names,
          containsAll([
            'github_get_viewer',
            'github_search',
            'github_repository_read',
            'github_repository_write',
            'github_issue_read',
            'github_issue_write',
            'github_pull_request_read',
            'github_pull_request_write',
            'github_release_read',
            'github_release_write',
            'github_actions_read',
            'github_actions_write',
            'github_secrets_read',
            'github_secrets_write',
          ]),
        );
        expect(names, isNot(contains('github_create_repository')));
        expect(names, isNot(contains('github_delete_repository')));
        expect(names, isNot(contains('github_merge_pull_request')));

        final repositoryWrite = tools.cast<Map>().firstWhere(
          (tool) => tool['name'] == 'github_repository_write',
        );
        final schema = repositoryWrite['inputSchema'] as Map;
        final action = (schema['properties'] as Map)['action'] as Map;
        expect(
          action['enum'],
          containsAll([
            'create_repository',
            'delete_repository',
            'delete_file',
          ]),
        );
      },
    );

    test('calls grouped search tool and returns MCP text content', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'total_count': 1,
            'incomplete_results': false,
            'items': [
              {
                'full_name': 'acme/app',
                'name': 'app',
                'owner': {'login': 'acme'},
                'private': false,
                'description': 'demo',
                'html_url': 'https://github.com/acme/app',
                'language': 'Dart',
                'default_branch': 'main',
                'stargazers_count': 42,
                'forks_count': 3,
                'open_issues_count': 1,
                'archived': false,
                'updated_at': '2026-07-26T00:00:00Z',
                'topics': ['flutter'],
                'license': {'spdx_id': 'MIT'},
              },
            ],
          }),
        );
        await request.response.close();
      });

      final engine = KelivoGithubMcpServerEngine(
        client: GitHubApiClient(
          baseUri: Uri.parse('http://${server.address.address}:${server.port}'),
        ),
      );
      addTearDown(engine.close);

      final response =
          await engine.handleMessage({
                'jsonrpc': '2.0',
                'id': 2,
                'method': 'tools/call',
                'params': {
                  'name': 'github_search',
                  'arguments': {
                    'action': 'repositories',
                    'query': 'flutter mcp language:Dart',
                  },
                },
              })
              as Map<String, dynamic>;

      final result = response['result'] as Map<String, dynamic>;
      expect(result['isError'], isFalse);
      final text = result['content'][0]['text'] as String;
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      expect(decoded['items'][0]['full_name'], 'acme/app');
      expect(decoded['items'][0]['license'], 'MIT');
    });

    test(
      'keeps legacy endpoint tool names callable for compatibility',
      () async {
        final requests = <HttpRequest>[];
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await server.close(force: true);
        });

        server.listen((request) async {
          requests.add(request);
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'total_count': 0,
              'incomplete_results': false,
              'items': <dynamic>[],
            }),
          );
          await request.response.close();
        });

        final engine = KelivoGithubMcpServerEngine(
          client: GitHubApiClient(
            baseUri: Uri.parse(
              'http://${server.address.address}:${server.port}',
            ),
          ),
        );
        addTearDown(engine.close);

        final response =
            await engine.handleMessage({
                  'jsonrpc': '2.0',
                  'id': 3,
                  'method': 'tools/call',
                  'params': {
                    'name': 'github_search_repositories',
                    'arguments': {'query': 'kelivo'},
                  },
                })
                as Map<String, dynamic>;

        final result = response['result'] as Map<String, dynamic>;
        expect(result['isError'], isFalse);
        expect(requests.single.uri.path, '/search/repositories');
      },
    );
  });
}
