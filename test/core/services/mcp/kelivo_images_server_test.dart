import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:Kelivo/core/services/mcp/kelivo_images/kelivo_images_server.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationCachePath() async => '$path/cache';

  @override
  Future<String?> getTemporaryPath() async => '$path/tmp';
}

void main() {
  group('Kelivo images MCP', () {
    late Directory root;
    late PathProviderPlatform previousPathProvider;
    late KelivoImagesMcpServerEngine engine;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('kelivo_images_mcp_test_');
      previousPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProviderPlatform(root.path);
      engine = KelivoImagesMcpServerEngine();
    });

    tearDown(() async {
      engine.close();
      PathProviderPlatform.instance = previousPathProvider;
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('advertises user-configurable image generation tool', () async {
      final response =
          await engine.handleMessage({
                'jsonrpc': '2.0',
                'id': 1,
                'method': 'tools/list',
              })
              as Map<String, dynamic>;

      final tools =
          (response['result'] as Map<String, dynamic>)['tools'] as List;
      final names = tools.map((tool) => (tool as Map)['name']);
      expect(
        names,
        containsAll(['kelivo_list_image_models', 'kelivo_generate_image']),
      );
      final tool = tools.cast<Map>().singleWhere(
        (tool) => tool['name'] == 'kelivo_generate_image',
      );
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;

      expect(props.keys, containsAll(['api_key', 'api_base_url', 'api_url']));
      expect(props['api_base_url']['default'], 'https://api.openai.com/v1');
      expect(schema['required'], containsAll(['prompt', 'api_key']));
    });

    test('scans image models from user-provided api_base_url', () async {
      late Uri requestUri;
      late String? authorization;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));

      server.listen((request) async {
        requestUri = request.uri;
        authorization = request.headers.value(HttpHeaders.authorizationHeader);
        await request.drain<void>();
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': [
              {'id': 'text-only-model'},
              {'id': 'gpt-image-1'},
              {'id': 'flux-pro'},
            ],
          }),
        );
        await request.response.close();
      });

      final result = await _call(engine, 'kelivo_list_image_models', {
        'api_key': 'test-secret',
        'api_base_url': 'http://${server.address.address}:${server.port}/v1',
      });

      expect(result['isError'], isFalse);
      expect(requestUri.path, '/v1/models');
      expect(authorization, 'Bearer test-secret');
      final decoded = jsonDecode(_text(result)) as Map<String, dynamic>;
      final ids = (decoded['models'] as List)
          .map((item) => (item as Map)['id'])
          .toList();
      expect(ids, containsAll(['gpt-image-1', 'flux-pro']));
      expect(ids, isNot(contains('text-only-model')));
      expect(decoded['instruction'], contains('choose one model'));
    });

    test('scans models from full models_url with custom filter', () async {
      late Uri requestUri;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));

      server.listen((request) async {
        requestUri = request.uri;
        await request.drain<void>();
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'models': ['draw-basic', 'paint-xl', 'chat-basic'],
          }),
        );
        await request.response.close();
      });

      final result = await _call(engine, 'kelivo_list_image_models', {
        'api_key': 'test-secret',
        'models_url':
            'http://${server.address.address}:${server.port}/custom/models',
        'filter': 'paint',
      });

      expect(result['isError'], isFalse);
      expect(requestUri.path, '/custom/models');
      final decoded = jsonDecode(_text(result)) as Map<String, dynamic>;
      final ids = (decoded['models'] as List)
          .map((item) => (item as Map)['id'])
          .toList();
      expect(ids, ['paint-xl']);
    });

    test('posts to custom api_url and saves base64 image response', () async {
      late Uri requestUri;
      late String? authorization;
      late Map<String, dynamic> requestBody;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));

      server.listen((request) async {
        requestUri = request.uri;
        authorization = request.headers.value(HttpHeaders.authorizationHeader);
        requestBody =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': [
              {
                'b64_json': base64Encode(const [1, 2, 3, 4]),
              },
            ],
          }),
        );
        await request.response.close();
      });

      final result = await _call(engine, 'kelivo_generate_image', {
        'prompt': 'draw a clean app icon',
        'api_key': 'test-secret',
        'api_url':
            'http://${server.address.address}:${server.port}/custom/images',
        'model': 'my-image-model',
        'output_format': 'webp',
        'save_path': 'generated/icon',
        'extra_body': {'style': 'flat'},
      });

      expect(result['isError'], isFalse);
      expect(requestUri.path, '/custom/images');
      expect(authorization, 'Bearer test-secret');
      expect(requestBody['prompt'], 'draw a clean app icon');
      expect(requestBody['model'], 'my-image-model');
      expect(requestBody['output_format'], 'webp');
      expect(requestBody['style'], 'flat');

      final decoded = jsonDecode(_text(result)) as Map<String, dynamic>;
      final image = (decoded['images'] as List).single as Map<String, dynamic>;
      final path = image['path'] as String;
      expect(
        path.endsWith('generated${Platform.pathSeparator}icon.webp'),
        isTrue,
      );
      expect(await File(path).readAsBytes(), const [1, 2, 3, 4]);
    });

    test('builds endpoint from user-provided api_base_url and path', () async {
      late Uri requestUri;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));

      server.listen((request) async {
        requestUri = request.uri;
        await request.drain<void>();
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': [
              {'url': 'https://example.com/generated.png'},
            ],
          }),
        );
        await request.response.close();
      });

      final result = await _call(engine, 'kelivo_generate_image', {
        'prompt': 'draw a landscape',
        'api_key': 'test-secret',
        'api_base_url': 'http://${server.address.address}:${server.port}/v1',
        'endpoint_path': 'images/generations',
      });

      expect(result['isError'], isFalse);
      expect(requestUri.path, '/v1/images/generations');
      expect(_text(result), contains('https://example.com/generated.png'));
    });

    test('rejects unsafe save paths before making the request', () async {
      var hitServer = false;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));
      server.listen((request) async {
        hitServer = true;
        await request.drain<void>();
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'data': []}));
        await request.response.close();
      });

      final result = await _call(engine, 'kelivo_generate_image', {
        'prompt': 'draw something',
        'api_key': 'test-secret',
        'api_url': 'http://${server.address.address}:${server.port}/images',
        'save_path': '../escape.png',
      });

      expect(result['isError'], isTrue);
      expect(_text(result), contains('save_path'));
      expect(hitServer, isFalse);
      expect(await File('${root.parent.path}/escape.png').exists(), isFalse);
    });
  });
}

Future<Map<String, dynamic>> _call(
  KelivoImagesMcpServerEngine engine,
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
  return ((content.first as Map)['text'] as String);
}
