import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mcp_client/mcp_client.dart' as mcp;
import 'package:path/path.dart' as p;

import '../../../../utils/app_directories.dart';
import '../in_memory_mcp_server.dart';

/// Built-in OpenAI-compatible image generation MCP server.
///
/// The API URL and API key are configured at the built-in MCP server level so
/// assistants no longer need to ask for credentials in the conversation.
class KelivoImagesMcpServerEngine implements KelivoInMemoryMcpServerEngine {
  KelivoImagesMcpServerEngine({
    http.Client? httpClient,
    this.apiBaseUrlProvider,
    this.apiKeyProvider,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  static const defaultApiBaseUrl = 'https://api.openai.com/v1';
  static const defaultEndpointPath = '/images/generations';
  static const defaultModelsEndpointPath = '/models';
  static const defaultModel = 'gpt-image-1';
  static const defaultOutputFormat = 'png';

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final String Function()? apiBaseUrlProvider;
  final String Function()? apiKeyProvider;
  bool _closed = false;

  String _configuredApiBaseUrl() {
    final configured = apiBaseUrlProvider?.call().trim() ?? '';
    return configured.isEmpty ? defaultApiBaseUrl : configured;
  }

  String _configuredApiKey() => apiKeyProvider?.call().trim() ?? '';

  @override
  Future<dynamic> handleMessage(dynamic message) async {
    if (_closed) return null;

    if (message is List) {
      final out = <dynamic>[];
      for (final m in message) {
        out.add(await _handleSingle(m));
      }
      return out;
    }
    return await _handleSingle(message);
  }

  Future<Map<String, dynamic>> _handleSingle(dynamic raw) async {
    try {
      if (raw is! Map) {
        return _error(null, code: -32600, message: 'Invalid Request');
      }
      final req = raw.cast<String, dynamic>();
      final id = req['id'];
      final method = (req['method'] ?? '').toString();
      final params = (req['params'] is Map)
          ? (req['params'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};

      switch (method) {
        case mcp.McpProtocol.methodInitialize:
          return _ok(
            id,
            result: {
              'serverInfo': {'name': '@kelivo/images', 'version': '0.1.0'},
              'protocolVersion': mcp.McpProtocol.defaultVersion,
              'capabilities': {
                'tools': {'listChanged': false},
              },
            },
          );

        case mcp.McpProtocol.methodListTools:
          return _ok(id, result: {'tools': _toolDefinitions()});

        case mcp.McpProtocol.methodCallTool:
          final name = (params['name'] ?? '').toString();
          final arguments = (params['arguments'] is Map)
              ? (params['arguments'] as Map).cast<String, dynamic>()
              : <String, dynamic>{};
          return switch (name) {
            'kelivo_list_image_models' => _ok(
              id,
              result: await _callListImageModels(arguments),
            ),
            'kelivo_generate_image' => _ok(
              id,
              result: await _callGenerateImage(arguments),
            ),
            _ => _error(id, code: -32101, message: 'Tool not found: $name'),
          };

        default:
          if (id == null) return _noop();
          return _error(id, code: -32601, message: 'Method not found: $method');
      }
    } catch (e) {
      return _error(null, code: -32603, message: 'Internal error: $e');
    }
  }

  Future<Map<String, dynamic>> _callGenerateImage(
    Map<String, dynamic> args,
  ) async {
    try {
      final request = _KelivoImageGenerationRequest.parse(
        args,
        configuredApiBaseUrl: _configuredApiBaseUrl(),
        configuredApiKey: _configuredApiKey(),
      );
      final response = await _httpClient.post(
        request.apiUri,
        headers: request.headers,
        body: jsonEncode(request.body),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _err(
          'Image API HTTP ${response.statusCode}: ${_bounded(response.body)}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return _err('Image API returned a non-object JSON body.');
      }
      final saved = await _saveImages(
        decoded.cast<String, dynamic>(),
        outputMime: request.outputMime,
        savePath: request.savePath,
      );
      if (saved.isEmpty) {
        return _err('Image API response did not contain url or b64_json data.');
      }

      final resultImages = [for (final image in saved) _publicImageInfo(image)];
      final result = {
        'ok': true,
        'api_url': request.apiUri.toString(),
        'model': request.model,
        'count': resultImages.length,
        'images': resultImages,
      };
      final text = const JsonEncoder.withIndent('  ').convert(result);
      return {
        'content': [
          {'type': 'text', 'text': text},
          for (final image in saved)
            if ((image['kind'] ?? '') == 'local_file')
              {
                'type': 'image',
                'data': image['data_base64'],
                'mimeType': image['mime_type'],
              },
        ],
        'structuredContent': result,
        'isStreaming': false,
        'isError': false,
      };
    } catch (e) {
      return _err(e.toString());
    }
  }

  Future<Map<String, dynamic>> _callListImageModels(
    Map<String, dynamic> args,
  ) async {
    try {
      final request = _KelivoImageModelsRequest.parse(
        args,
        configuredApiBaseUrl: _configuredApiBaseUrl(),
        configuredApiKey: _configuredApiKey(),
      );
      final response = await _httpClient.get(
        request.modelsUri,
        headers: request.headers,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _err(
          'Models API HTTP ${response.statusCode}: ${_bounded(response.body)}',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return _err('Models API returned a non-object JSON body.');
      }

      final allModels = _extractModels(decoded.cast<String, dynamic>());
      final filtered = _filterImageModels(allModels, request.filter);
      final result = {
        'ok': true,
        'models_url': request.modelsUri.toString(),
        'count': filtered.length,
        'models': filtered,
        'instruction': filtered.isEmpty
            ? 'No obvious image models were found. Ask the user to provide the image model name manually.'
            : 'Ask the user to choose one model id from models, then call kelivo_generate_image with that model.',
      };
      return {
        'content': [
          {
            'type': 'text',
            'text': const JsonEncoder.withIndent('  ').convert(result),
          },
        ],
        'structuredContent': result,
        'isStreaming': false,
        'isError': false,
      };
    } catch (e) {
      return _err(e.toString());
    }
  }

  static List<Map<String, dynamic>> _extractModels(Map<String, dynamic> body) {
    final raw = body['data'] ?? body['models'];
    if (raw is! List) return const [];
    final models = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is String) {
        models.add({'id': item});
        continue;
      }
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      final id = (map['id'] ?? map['name'] ?? map['model'] ?? '')
          .toString()
          .trim();
      if (id.isEmpty) continue;
      models.add({
        'id': id,
        if (map['owned_by'] != null) 'owned_by': map['owned_by'],
        if (map['object'] != null) 'object': map['object'],
        if (map['created'] != null) 'created': map['created'],
      });
    }
    return models;
  }

  static List<Map<String, dynamic>> _filterImageModels(
    List<Map<String, dynamic>> models,
    String filter,
  ) {
    final normalizedFilter = filter.trim().toLowerCase();
    final keywords = normalizedFilter.isEmpty
        ? const [
            'image',
            'img',
            'dall-e',
            'gpt-image',
            'vision',
            'flux',
            'sd',
            'stable-diffusion',
            'midjourney',
            'mj',
            'kolors',
            'imagen',
          ]
        : normalizedFilter
              .split(RegExp(r'[\s,]+'))
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false);
    final matched = models
        .where((model) {
          final id = (model['id'] ?? '').toString().toLowerCase();
          return keywords.any(id.contains);
        })
        .toList(growable: false);
    return matched.isEmpty ? models : matched;
  }

  Future<List<Map<String, dynamic>>> _saveImages(
    Map<String, dynamic> response, {
    required String outputMime,
    required String? savePath,
  }) async {
    final data = response['data'];
    if (data is! List) return const [];

    final results = <Map<String, dynamic>>[];
    var index = 0;
    for (final item in data) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      final url = (map['url'] ?? '').toString().trim();
      if (url.isNotEmpty) {
        results.add({
          'kind': 'remote_url',
          'url': url,
          'markdown': '![image]($url)',
        });
        continue;
      }
      final b64 = (map['b64_json'] ?? '').toString().trim();
      if (b64.isEmpty) continue;
      final bytes = _decodeBase64Image(b64);
      final file = await _writeImageFile(
        bytes,
        outputMime: outputMime,
        savePath: savePath,
        index: index,
      );
      results.add({
        'kind': 'local_file',
        'path': file.path,
        'mime_type': outputMime,
        'size_bytes': bytes.length,
        'markdown': '![image](${file.path})',
        'data_base64': base64Encode(bytes),
      });
      index += 1;
    }
    return results;
  }

  Future<File> _writeImageFile(
    List<int> bytes, {
    required String outputMime,
    required String? savePath,
    required int index,
  }) async {
    final imagesDir = await AppDirectories.getImagesDirectory();
    await imagesDir.create(recursive: true);
    final ext = AppDirectories.extFromMime(outputMime);
    final resolved = _resolveSavePath(
      imagesDir.path,
      savePath: savePath,
      ext: ext,
      index: index,
    );
    await Directory(p.dirname(resolved)).create(recursive: true);
    final file = File(resolved);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static String _resolveSavePath(
    String rootPath, {
    required String? savePath,
    required String ext,
    required int index,
  }) {
    final rootNorm = p.normalize(rootPath);
    final fallback = 'mcp_image_${DateTime.now().microsecondsSinceEpoch}.$ext';
    final raw = (savePath ?? '').trim();
    final relative = raw.isEmpty ? fallback : raw.replaceAll('\\', '/');
    _validateRelativeSavePath(relative);
    final withoutTraversal = p.normalize(relative);
    final hasExtension = p.extension(withoutTraversal).isNotEmpty;
    final baseRelative = hasExtension
        ? withoutTraversal
        : '$withoutTraversal.$ext';
    final indexedRelative = index == 0
        ? baseRelative
        : '${p.withoutExtension(baseRelative)}_${index + 1}${p.extension(baseRelative)}';
    final absolute = p.normalize(p.join(rootNorm, indexedRelative));
    if (absolute != rootNorm && !p.isWithin(rootNorm, absolute)) {
      throw ArgumentError('save_path escapes images directory.');
    }
    return absolute;
  }

  static void _validateRelativeSavePath(String relative) {
    if (Uri.tryParse(relative)?.hasScheme == true) {
      throw ArgumentError('save_path must be a relative path under images.');
    }
    if (p.isAbsolute(relative)) {
      throw ArgumentError('save_path must be relative, not absolute.');
    }
    final withoutTraversal = p.normalize(relative);
    if (withoutTraversal == '..' ||
        withoutTraversal.startsWith('..${p.separator}')) {
      throw ArgumentError('save_path cannot contain .. traversal.');
    }
  }

  static Map<String, dynamic> _publicImageInfo(Map<String, dynamic> image) {
    final copy = Map<String, dynamic>.from(image);
    copy.remove('data_base64');
    return copy;
  }

  static List<int> _decodeBase64Image(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'\s'), '');
    if (cleaned.contains('-') || cleaned.contains('_')) {
      return base64Url.decode(cleaned);
    }
    return base64Decode(cleaned);
  }

  static String _bounded(String text, {int maxLength = 1200}) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  Map<String, dynamic> _ok(dynamic id, {required Map<String, dynamic> result}) {
    return {'jsonrpc': '2.0', if (id != null) 'id': id, 'result': result};
  }

  Map<String, dynamic> _error(
    dynamic id, {
    required int code,
    required String message,
  }) {
    return {
      'jsonrpc': '2.0',
      if (id != null) 'id': id,
      'error': {'code': code, 'message': message},
    };
  }

  Map<String, dynamic> _noop() => {'jsonrpc': '2.0'};

  static Map<String, dynamic> _err(String message) => {
    'content': [
      {'type': 'text', 'text': message},
    ],
    'isStreaming': false,
    'isError': true,
  };

  List<Map<String, dynamic>> _toolDefinitions() => [
    {
      'name': 'kelivo_list_image_models',
      'description':
          '根据 @kelivo/images 基础设置中的 API URL 和 Key 扫描可用模型。用户需要选择图片模型时先调用此工具，返回候选模型后再询问用户使用哪个模型生成图片。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'models_endpoint_path': {
            'type': 'string',
            'description': '追加到已配置 API URL 后的模型列表端点路径。',
            'default': defaultModelsEndpointPath,
          },
          'filter': {
            'type': 'string',
            'description': '可选的模型 ID 关键词，支持用逗号或空格分隔。默认使用常见图片模型关键词。',
          },
          'headers': {
            'type': 'object',
            'description': '可选的附加 HTTP 头。Authorization 默认由已配置 API Key 设置。',
          },
        },
        'required': [],
      },
    },
    {
      'name': 'kelivo_generate_image',
      'description':
          '通过兼容 OpenAI 的 Images API 生成图片。API URL 和 Key 来自 @kelivo/images 基础设置，不要在对话中向用户索要或传递。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'prompt': {'type': 'string', 'description': '发送给图片生成 API 的图片提示词。'},
          'endpoint_path': {
            'type': 'string',
            'description': '追加到已配置 API URL 后的端点路径。',
            'default': defaultEndpointPath,
          },
          'model': {
            'type': 'string',
            'description': '图片模型名称。',
            'default': defaultModel,
          },
          'output_format': {
            'type': 'string',
            'description': 'base64 响应使用的输出格式。',
            'enum': ['png', 'jpeg', 'jpg', 'webp'],
            'default': defaultOutputFormat,
          },
          'size': {'type': 'string', 'description': '可选图片尺寸，例如 1024x1024。'},
          'quality': {'type': 'string', 'description': '可选的供应商特定质量参数。'},
          'n': {'type': 'integer', 'description': '可选的生成图片数量。', 'default': 1},
          'save_path': {
            'type': 'string',
            'description': 'Kelivo 图片目录下的可选相对保存路径。会拒绝绝对路径和 ..。',
          },
          'extra_body': {
            'type': 'object',
            'description': '可选的供应商特定 JSON 请求体字段。',
          },
          'headers': {
            'type': 'object',
            'description': '可选的附加 HTTP 头。Authorization 默认由已配置 API Key 设置。',
          },
        },
        'required': ['prompt'],
      },
    },
  ];

  @override
  void close() {
    _closed = true;
    if (_ownsHttpClient) _httpClient.close();
  }
}

class _KelivoImageGenerationRequest {
  const _KelivoImageGenerationRequest({
    required this.apiUri,
    required this.headers,
    required this.body,
    required this.model,
    required this.outputMime,
    required this.savePath,
  });

  final Uri apiUri;
  final Map<String, String> headers;
  final Map<String, dynamic> body;
  final String model;
  final String outputMime;
  final String? savePath;

  static _KelivoImageGenerationRequest parse(
    Map<String, dynamic> args, {
    required String configuredApiBaseUrl,
    required String configuredApiKey,
  }) {
    final prompt = _requiredString(args, 'prompt');
    final apiKey = _requiredString(
      args,
      'api_key',
      fallback: configuredApiKey,
      errorMessage:
          '@kelivo/images 尚未配置 API Key，请在 MCP 设置中打开 @kelivo/images 的基础设置填写 URL 和 Key。',
    );
    final model = _stringArg(
      args,
      'model',
      KelivoImagesMcpServerEngine.defaultModel,
    );
    final apiUri = _apiUri(args, configuredApiBaseUrl);
    final outputFormat = _stringArg(
      args,
      'output_format',
      KelivoImagesMcpServerEngine.defaultOutputFormat,
    ).toLowerCase();
    final outputMime = switch (outputFormat) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      _ => throw ArgumentError(
        'output_format must be png, jpeg, jpg, or webp.',
      ),
    };

    final body = <String, dynamic>{
      'model': model,
      'prompt': prompt,
      'output_format': outputFormat == 'jpg' ? 'jpeg' : outputFormat,
    };
    _copyIfPresent(args, body, 'size');
    _copyIfPresent(args, body, 'quality');
    _copyIfPresent(args, body, 'n');
    final extraBody = args['extra_body'];
    if (extraBody is Map) {
      extraBody.forEach((key, value) {
        if (key == null || value == null) return;
        body[key.toString()] = value;
      });
    }

    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
      HttpHeaders.acceptHeader: ContentType.json.mimeType,
      HttpHeaders.authorizationHeader: 'Bearer $apiKey',
    };
    final extraHeaders = args['headers'];
    if (extraHeaders is Map) {
      extraHeaders.forEach((key, value) {
        if (key == null || value == null) return;
        headers[key.toString()] = value.toString();
      });
    }

    final savePath = (args['save_path'] ?? '').toString().trim().isEmpty
        ? null
        : args['save_path'].toString().trim();
    if (savePath != null) {
      KelivoImagesMcpServerEngine._validateRelativeSavePath(
        savePath.replaceAll('\\', '/'),
      );
    }

    return _KelivoImageGenerationRequest(
      apiUri: apiUri,
      headers: headers,
      body: body,
      model: model,
      outputMime: outputMime,
      savePath: savePath,
    );
  }

  static Uri _apiUri(Map<String, dynamic> args, String configuredApiBaseUrl) {
    final full = (args['api_url'] ?? '').toString().trim();
    if (full.isNotEmpty) return _httpUri(full, fieldName: 'api_url');

    var base = _stringArg(
      args,
      'api_base_url',
      configuredApiBaseUrl.trim().isEmpty
          ? KelivoImagesMcpServerEngine.defaultApiBaseUrl
          : configuredApiBaseUrl.trim(),
    );
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    var path = _stringArg(
      args,
      'endpoint_path',
      KelivoImagesMcpServerEngine.defaultEndpointPath,
    );
    if (!path.startsWith('/')) path = '/$path';
    return _httpUri('$base$path', fieldName: 'api_base_url');
  }

  static Uri _httpUri(String raw, {required String fieldName}) {
    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw ArgumentError('$fieldName must be an http(s) URL.');
    }
    return uri;
  }

  static String _requiredString(
    Map<String, dynamic> args,
    String key, {
    String? fallback,
    String? errorMessage,
  }) {
    final value = (args[key] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
    final fallbackValue = fallback?.trim() ?? '';
    if (fallbackValue.isNotEmpty) return fallbackValue;
    throw ArgumentError(errorMessage ?? '$key is required.');
  }

  static String _stringArg(
    Map<String, dynamic> args,
    String key,
    String defaultValue,
  ) {
    final value = (args[key] ?? '').toString().trim();
    return value.isEmpty ? defaultValue : value;
  }

  static void _copyIfPresent(
    Map<String, dynamic> source,
    Map<String, dynamic> target,
    String key,
  ) {
    final value = source[key];
    if (value == null) return;
    if (value is String && value.trim().isEmpty) return;
    target[key] = value;
  }
}

class _KelivoImageModelsRequest {
  const _KelivoImageModelsRequest({
    required this.modelsUri,
    required this.headers,
    required this.filter,
  });

  final Uri modelsUri;
  final Map<String, String> headers;
  final String filter;

  static _KelivoImageModelsRequest parse(
    Map<String, dynamic> args, {
    required String configuredApiBaseUrl,
    required String configuredApiKey,
  }) {
    final apiKey = _KelivoImageGenerationRequest._requiredString(
      args,
      'api_key',
      fallback: configuredApiKey,
      errorMessage:
          '@kelivo/images 尚未配置 API Key，请在 MCP 设置中打开 @kelivo/images 的基础设置填写 URL 和 Key。',
    );
    final modelsUri = _modelsUri(args, configuredApiBaseUrl);
    final headers = <String, String>{
      HttpHeaders.acceptHeader: ContentType.json.mimeType,
      HttpHeaders.authorizationHeader: 'Bearer $apiKey',
    };
    final extraHeaders = args['headers'];
    if (extraHeaders is Map) {
      extraHeaders.forEach((key, value) {
        if (key == null || value == null) return;
        headers[key.toString()] = value.toString();
      });
    }

    return _KelivoImageModelsRequest(
      modelsUri: modelsUri,
      headers: headers,
      filter: (args['filter'] ?? '').toString().trim(),
    );
  }

  static Uri _modelsUri(
    Map<String, dynamic> args,
    String configuredApiBaseUrl,
  ) {
    final full = (args['models_url'] ?? '').toString().trim();
    if (full.isNotEmpty) {
      return _KelivoImageGenerationRequest._httpUri(
        full,
        fieldName: 'models_url',
      );
    }

    var base = _KelivoImageGenerationRequest._stringArg(
      args,
      'api_base_url',
      configuredApiBaseUrl.trim().isEmpty
          ? KelivoImagesMcpServerEngine.defaultApiBaseUrl
          : configuredApiBaseUrl.trim(),
    );
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    var path = _KelivoImageGenerationRequest._stringArg(
      args,
      'models_endpoint_path',
      KelivoImagesMcpServerEngine.defaultModelsEndpointPath,
    );
    if (!path.startsWith('/')) path = '/$path';
    return _KelivoImageGenerationRequest._httpUri(
      '$base$path',
      fieldName: 'api_base_url',
    );
  }
}
