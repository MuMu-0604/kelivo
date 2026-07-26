import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/mcp/kelivo_files/kelivo_files_server.dart';

void main() {
  group('Kelivo files MCP', () {
    late Directory root;
    late KelivoFilesMcpServerEngine engine;

    setUp(() async {
      KelivoFilesMcpServerEngine.resetRememberedWorkspaceForTests();
      root = await Directory.systemTemp.createTemp('kelivo_files_mcp_test_');
      engine = KelivoFilesMcpServerEngine(
        workspaceRootsProvider: () async => {'documents': root},
      );
    });

    tearDown(() async {
      engine.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('advertises safe local file tools', () async {
      final response =
          await engine.handleMessage({
                'jsonrpc': '2.0',
                'id': 1,
                'method': 'tools/list',
              })
              as Map<String, dynamic>;

      final tools =
          (response['result'] as Map<String, dynamic>)['tools'] as List;
      expect(
        tools.map((tool) => (tool as Map)['name']),
        containsAll(<String>[
          'kelivo_list_file_workspaces',
          'kelivo_get_current_file_workspace',
          'kelivo_set_current_file_workspace',
          'kelivo_search_files',
          'kelivo_search_text',
          'kelivo_list_recent_files',
          'kelivo_hash_file',
          'kelivo_detect_mime_type',
          'kelivo_preview_file',
          'kelivo_copy_file',
          'kelivo_zip_files',
          'kelivo_unzip_file',
          'kelivo_delete_files',
          'kelivo_create_text_file',
          'kelivo_read_text_file',
          'kelivo_read_file_base64',
          'kelivo_write_file_base64',
          'kelivo_delete_file',
          'kelivo_move_file',
        ]),
      );
      final createTool = tools.cast<Map>().firstWhere(
        (tool) => tool['name'] == 'kelivo_create_text_file',
      );
      expect(createTool['description'], contains('创建新的 UTF-8 文本文件'));
      final workspaceSchema =
          ((createTool['inputSchema'] as Map)['properties'] as Map)['workspace']
              as Map;
      expect(workspaceSchema['description'], contains('工作区'));
      expect(workspaceSchema['enum'], contains('phone_storage'));
    });

    test('creates, reads, appends, moves, and deletes a text file', () async {
      final created = await _call(engine, 'kelivo_create_text_file', const {
        'workspace': 'documents',
        'path': 'notes/hello.txt',
        'content': 'hello',
      });
      expect(created['isError'], isFalse);
      expect(
        await File('${root.path}/notes/hello.txt').readAsString(),
        'hello',
      );

      await _call(engine, 'kelivo_append_text_file', const {
        'path': 'notes/hello.txt',
        'content': ' world',
      });
      final read = await _call(engine, 'kelivo_read_text_file', const {
        'path': 'notes/hello.txt',
      });
      expect(jsonDecode(_text(read))['content'], 'hello world');

      final moved = await _call(engine, 'kelivo_move_file', const {
        'from_path': 'notes/hello.txt',
        'to_path': 'notes/greeting.txt',
      });
      expect(moved['isError'], isFalse);
      expect(await File('${root.path}/notes/greeting.txt').exists(), isTrue);

      final deleted = await _call(engine, 'kelivo_delete_file', const {
        'path': 'notes/greeting.txt',
      });
      expect(deleted['isError'], isFalse);
      expect(await File('${root.path}/notes/greeting.txt').exists(), isFalse);
    });

    test('rejects absolute paths and traversal', () async {
      final absolute = await _call(engine, 'kelivo_create_text_file', {
        'path': '${root.path}/escape.txt',
        'content': 'bad',
      });
      expect(absolute['isError'], isTrue);
      expect(_text(absolute), contains('relative'));

      final traversal = await _call(engine, 'kelivo_create_text_file', const {
        'path': '../escape.txt',
        'content': 'bad',
      });
      expect(traversal['isError'], isTrue);
      expect(_text(traversal), contains('..'));
      expect(await File('${root.parent.path}/escape.txt').exists(), isFalse);
    });

    test('does not overwrite unless explicitly requested', () async {
      await File('${root.path}/same.txt').writeAsString('old');

      final blocked = await _call(engine, 'kelivo_create_text_file', const {
        'path': 'same.txt',
        'content': 'new',
      });
      expect(blocked['isError'], isTrue);
      expect(await File('${root.path}/same.txt').readAsString(), 'old');

      final overwritten = await _call(engine, 'kelivo_create_text_file', const {
        'path': 'same.txt',
        'content': 'new',
        'overwrite': true,
      });
      expect(overwritten['isError'], isFalse);
      expect(await File('${root.path}/same.txt').readAsString(), 'new');
    });

    test('defaults to phone storage when available', () async {
      final phoneRoot = await Directory.systemTemp.createTemp(
        'kelivo_files_mcp_default_phone_storage_test_',
      );
      engine.close();
      engine = KelivoFilesMcpServerEngine(
        workspaceRootsProvider: () async => {
          'documents': root,
          'phone_storage': phoneRoot,
        },
      );
      addTearDown(() async {
        if (await phoneRoot.exists()) await phoneRoot.delete(recursive: true);
      });

      final current = await _call(
        engine,
        'kelivo_get_current_file_workspace',
        const {},
      );
      expect(jsonDecode(_text(current))['current_workspace'], 'phone_storage');

      final created = await _call(engine, 'kelivo_create_text_file', const {
        'path': 'Download/default.txt',
        'content': 'visible file',
      });
      expect(created['isError'], isFalse);
      expect(
        await File('${phoneRoot.path}/Download/default.txt').readAsString(),
        'visible file',
      );
      expect(await File('${root.path}/Download/default.txt').exists(), isFalse);
    });

    test('switches current workspace and uses it by default', () async {
      final scratch = await Directory.systemTemp.createTemp(
        'kelivo_files_mcp_scratch_test_',
      );
      engine.close();
      engine = KelivoFilesMcpServerEngine(
        workspaceRootsProvider: () async => {
          'documents': root,
          'scratch': scratch,
        },
      );
      addTearDown(() async {
        if (await scratch.exists()) await scratch.delete(recursive: true);
      });

      final switched = await _call(
        engine,
        'kelivo_set_current_file_workspace',
        const {'workspace': 'scratch'},
      );
      expect(switched['isError'], isFalse);

      final created = await _call(engine, 'kelivo_create_text_file', const {
        'path': 'draft.txt',
        'content': 'scratch file',
      });
      expect(created['isError'], isFalse);
      expect(
        await File('${scratch.path}/draft.txt').readAsString(),
        'scratch file',
      );
      expect(await File('${root.path}/draft.txt').exists(), isFalse);

      final current = await _call(
        engine,
        'kelivo_get_current_file_workspace',
        const {},
      );
      expect(jsonDecode(_text(current))['current_workspace'], 'scratch');
    });

    test('keeps current workspace across engine reconnects', () async {
      final scratch = await Directory.systemTemp.createTemp(
        'kelivo_files_mcp_reconnect_scratch_test_',
      );
      engine.close();
      engine = KelivoFilesMcpServerEngine(
        workspaceRootsProvider: () async => {
          'documents': root,
          'scratch': scratch,
        },
      );
      addTearDown(() async {
        if (await scratch.exists()) await scratch.delete(recursive: true);
      });

      await _call(engine, 'kelivo_set_current_file_workspace', const {
        'workspace': 'scratch',
      });
      engine.close();
      engine = KelivoFilesMcpServerEngine(
        workspaceRootsProvider: () async => {
          'documents': root,
          'scratch': scratch,
        },
      );

      final created = await _call(engine, 'kelivo_create_text_file', const {
        'path': 'after-reconnect.txt',
        'content': 'still scratch',
      });

      expect(created['isError'], isFalse);
      expect(
        await File('${scratch.path}/after-reconnect.txt').readAsString(),
        'still scratch',
      );
      expect(await File('${root.path}/after-reconnect.txt').exists(), isFalse);
    });

    test('moves files across workspaces when requested', () async {
      final exports = await Directory.systemTemp.createTemp(
        'kelivo_files_mcp_exports_test_',
      );
      engine.close();
      engine = KelivoFilesMcpServerEngine(
        workspaceRootsProvider: () async => {
          'documents': root,
          'exports': exports,
        },
      );
      addTearDown(() async {
        if (await exports.exists()) await exports.delete(recursive: true);
      });
      await File('${root.path}/report.txt').writeAsString('report');

      final moved = await _call(engine, 'kelivo_move_file', const {
        'from_workspace': 'documents',
        'from_path': 'report.txt',
        'to_workspace': 'exports',
        'to_path': 'report.txt',
      });

      expect(moved['isError'], isFalse);
      expect(await File('${root.path}/report.txt').exists(), isFalse);
      expect(await File('${exports.path}/report.txt').readAsString(), 'report');
    });

    test(
      'supports phone storage absolute paths under the storage root',
      () async {
        final phoneRoot = await Directory.systemTemp.createTemp(
          'kelivo_files_mcp_phone_storage_test_',
        );
        engine.close();
        engine = KelivoFilesMcpServerEngine(
          workspaceRootsProvider: () async => {
            'documents': root,
            'phone_storage': phoneRoot,
          },
        );
        addTearDown(() async {
          if (await phoneRoot.exists()) await phoneRoot.delete(recursive: true);
        });

        final created = await _call(engine, 'kelivo_create_text_file', {
          'workspace': 'phone_storage',
          'path': '/storage/emulated/0/Download/test.txt',
          'content': 'phone file',
        });

        expect(created['isError'], isFalse);
        expect(
          await File('${phoneRoot.path}/Download/test.txt').readAsString(),
          'phone file',
        );

        final escaped = await _call(engine, 'kelivo_stat_file', const {
          'workspace': 'phone_storage',
          'path': '/data/local/tmp/secret.txt',
        });
        expect(escaped['isError'], isTrue);
      },
    );

    test('reads and writes binary files with base64', () async {
      final written = await _call(engine, 'kelivo_write_file_base64', const {
        'path': 'bin/blob.dat',
        'content_base64': 'AAECAw==',
      });
      expect(written['isError'], isFalse);

      final read = await _call(engine, 'kelivo_read_file_base64', const {
        'path': 'bin/blob.dat',
      });
      final decoded = jsonDecode(_text(read)) as Map<String, dynamic>;
      expect(decoded['content_base64'], 'AAECAw==');
      expect(decoded['bytes'], 4);
    });

    test('searches file names and text content', () async {
      await File('${root.path}/alpha_notes.txt').writeAsString('hello needle');
      await Directory('${root.path}/nested').create();
      await File('${root.path}/nested/beta.txt').writeAsString('nothing');

      final fileMatches = await _call(engine, 'kelivo_search_files', const {
        'query': 'alpha',
      });
      final files = jsonDecode(_text(fileMatches)) as Map<String, dynamic>;
      expect((files['matches'] as List).single['path'], 'alpha_notes.txt');

      final textMatches = await _call(engine, 'kelivo_search_text', const {
        'query': 'needle',
      });
      final text = jsonDecode(_text(textMatches)) as Map<String, dynamic>;
      expect((text['matches'] as List).single['path'], 'alpha_notes.txt');
      expect((text['matches'] as List).single['preview'], contains('needle'));
    });

    test('filters, sorts, and lists recent files', () async {
      final oldFile = File('${root.path}/a.txt');
      final middleFile = File('${root.path}/b.md');
      final newFile = File('${root.path}/c.txt');
      await oldFile.writeAsString('old');
      await middleFile.writeAsString('middle');
      await newFile.writeAsString('new');
      await oldFile.setLastModified(DateTime(2026, 1, 1));
      await middleFile.setLastModified(DateTime(2026, 1, 2));
      await newFile.setLastModified(DateTime(2026, 1, 3));

      final listed = await _call(engine, 'kelivo_list_files', const {
        'type': 'file',
        'extension': 'txt',
        'sort_by': 'modified',
        'descending': true,
      });
      final listJson = jsonDecode(_text(listed)) as Map<String, dynamic>;
      final entries = listJson['entries'] as List;
      expect(entries.map((entry) => entry['path']), ['c.txt', 'a.txt']);

      final recent = await _call(engine, 'kelivo_list_recent_files', const {
        'extension': '.txt',
        'limit': 1,
      });
      final recentJson = jsonDecode(_text(recent)) as Map<String, dynamic>;
      expect((recentJson['entries'] as List).single['path'], 'c.txt');
    });

    test('copies files, computes hashes, and batch deletes', () async {
      await File('${root.path}/source.txt').writeAsString('hash me');
      await Directory('${root.path}/batch').create();
      await File('${root.path}/batch/a.txt').writeAsString('a');
      await File('${root.path}/batch/b.txt').writeAsString('b');

      final copied = await _call(engine, 'kelivo_copy_file', const {
        'from_path': 'source.txt',
        'to_path': 'copied/source.txt',
      });
      expect(copied['isError'], isFalse);
      expect(
        await File('${root.path}/copied/source.txt').readAsString(),
        'hash me',
      );

      final hashed = await _call(engine, 'kelivo_hash_file', const {
        'path': 'copied/source.txt',
        'algorithm': 'sha256',
      });
      final hashJson = jsonDecode(_text(hashed)) as Map<String, dynamic>;
      expect(hashJson['hash'], hasLength(64));

      final deleted = await _call(engine, 'kelivo_delete_files', const {
        'paths': ['batch/a.txt', 'batch/b.txt'],
      });
      final deleteJson = jsonDecode(_text(deleted)) as Map<String, dynamic>;
      expect(deleteJson['deleted_count'], 2);
      expect(await File('${root.path}/batch/a.txt').exists(), isFalse);
      expect(await File('${root.path}/batch/b.txt').exists(), isFalse);
    });

    test(
      'detects mime types and previews text, binary, directories, and zips',
      () async {
        await File('${root.path}/note.txt').writeAsString('hello preview');
        await File(
          '${root.path}/image.png',
        ).writeAsBytes(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

        final mime = await _call(engine, 'kelivo_detect_mime_type', const {
          'path': 'image.png',
        });
        final mimeJson = jsonDecode(_text(mime)) as Map<String, dynamic>;
        expect(mimeJson['mime_type'], 'image/png');
        expect(mimeJson['source'], 'magic');

        final textPreview = await _call(engine, 'kelivo_preview_file', const {
          'path': 'note.txt',
        });
        expect(jsonDecode(_text(textPreview))['preview'], 'hello preview');

        final dirPreview = await _call(engine, 'kelivo_preview_file', const {
          'path': '',
          'limit': 2,
        });
        final dirJson = jsonDecode(_text(dirPreview)) as Map<String, dynamic>;
        expect(dirJson['kind'], 'directory');
        expect(dirJson['entries'], isA<List>());

        final zipped = await _call(engine, 'kelivo_zip_files', const {
          'paths': ['note.txt'],
          'destination_path': 'packed.zip',
        });
        expect(zipped['isError'], isFalse);

        final zipPreview = await _call(engine, 'kelivo_preview_file', const {
          'path': 'packed.zip',
        });
        final zipJson = jsonDecode(_text(zipPreview)) as Map<String, dynamic>;
        expect(zipJson['kind'], 'archive');
        expect((zipJson['entries'] as List).single['path'], 'note.txt');
      },
    );

    test('zips and unzips files safely', () async {
      await Directory('${root.path}/src').create();
      await File('${root.path}/src/a.txt').writeAsString('A');
      await File('${root.path}/src/b.txt').writeAsString('B');

      final zipped = await _call(engine, 'kelivo_zip_files', const {
        'paths': ['src'],
        'destination_path': 'archive.zip',
        'include_root_dir': true,
      });
      final zipJson = jsonDecode(_text(zipped)) as Map<String, dynamic>;
      expect(zipJson['ok'], isTrue);
      expect(await File('${root.path}/archive.zip').exists(), isTrue);

      final unzipped = await _call(engine, 'kelivo_unzip_file', const {
        'zip_path': 'archive.zip',
        'destination_path': 'out',
      });
      final unzipJson = jsonDecode(_text(unzipped)) as Map<String, dynamic>;
      expect(unzipJson['ok'], isTrue);
      expect(await File('${root.path}/out/src/a.txt').readAsString(), 'A');
      expect(await File('${root.path}/out/src/b.txt').readAsString(), 'B');
    });

    test('pages long text without splitting surrogate pairs', () async {
      final smile = String.fromCharCode(0x1F600);
      await File('${root.path}/unicode.txt').writeAsString('${smile}abcdef');

      final first = await _call(engine, 'kelivo_read_text_file', const {
        'path': 'unicode.txt',
        'max_length': 1,
      });
      final decodedFirst = jsonDecode(_text(first)) as Map<String, dynamic>;
      expect(decodedFirst['content'], smile);
      expect(decodedFirst['next_start_index'], 2);

      final second = await _call(engine, 'kelivo_read_text_file', const {
        'path': 'unicode.txt',
        'start_index': 2,
        'max_length': 3,
      });
      expect(jsonDecode(_text(second))['content'], 'abc');
    });
  });
}

Future<Map<String, dynamic>> _call(
  KelivoFilesMcpServerEngine engine,
  String toolName,
  Map<String, dynamic> arguments,
) async {
  final response =
      await engine.handleMessage({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'tools/call',
            'params': {'name': toolName, 'arguments': arguments},
          })
          as Map<String, dynamic>;
  return ((response['result'] as Map).cast<String, dynamic>());
}

String _text(Map<String, dynamic> result) {
  final content = result['content'] as List;
  return ((content.single as Map)['text'] as String);
}
