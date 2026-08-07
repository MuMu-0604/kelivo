import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';

ProviderConfig _openAiConfig(String baseUrl, {bool responses = false}) {
  return ProviderConfig(
    id: 'OpenAITest',
    enabled: true,
    name: 'OpenAITest',
    apiKey: 'test-key',
    baseUrl: baseUrl,
    providerType: ProviderKind.openai,
    useResponseApi: responses,
  );
}

void main() {
  late Directory tempDir;
  late String docxPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kelivo_office_doc_');
    final file = File('${tempDir.path}/test.docx');
    await file.writeAsBytes([1, 2, 3, 4]);
    docxPath = file.path;
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('routes DOCX to Chat Completions file part', () async {
    final body = await _sendAndCaptureRequestBody((baseUrl) {
      return ChatApiService.sendMessageStream(
        config: _openAiConfig(baseUrl),
        modelId: 'gpt-4.1',
        messages: const [
          {'role': 'user', 'content': 'summarize this'},
        ],
        userMediaPaths: [docxPath],
        stream: false,
      ).toList();
    });

    final messages = (body['messages'] as List).cast<dynamic>();
    final content = ((messages.single as Map)['content'] as List)
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList(growable: false);
    final filePart = content.singleWhere((part) => part['type'] == 'file');
    expect(filePart['file']['filename'], 'test.docx');
    expect(
      (filePart['file']['file_data'] as String).startsWith(
        'data:application/vnd.openxmlformats-officedocument.wordprocessingml.document;base64,',
      ),
      isTrue,
    );
  });

  test('routes DOCX to Responses input_file part', () async {
    final body = await _sendAndCaptureResponsesBody((baseUrl) {
      return ChatApiService.sendMessageStream(
        config: _openAiConfig(baseUrl, responses: true),
        modelId: 'gpt-4.1',
        messages: const [
          {'role': 'user', 'content': 'summarize this'},
        ],
        userMediaPaths: [docxPath],
        stream: false,
      ).toList();
    });

    final input = (body['input'] as List).cast<dynamic>();
    final user =
        input.firstWhere((item) => (item as Map)['role'] == 'user') as Map;
    final content = (user['content'] as List)
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList(growable: false);
    final filePart = content.singleWhere(
      (part) => part['type'] == 'input_file',
    );
    expect(filePart['filename'], 'test.docx');
    expect(
      (filePart['file_data'] as String).startsWith(
        'data:application/vnd.openxmlformats-officedocument.wordprocessingml.document;base64,',
      ),
      isTrue,
    );
  });
}

Future<Map<String, dynamic>> _sendAndCaptureRequestBody(
  Future<List<dynamic>> Function(String baseUrl) sendRequest,
) async {
  Map<String, dynamic>? requestBody;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final baseUrl = 'http://${server.address.address}:${server.port}/v1';
  try {
    server.listen((request) async {
      final rawBody = await utf8.decoder.bind(request).join();
      requestBody = (jsonDecode(rawBody) as Map).cast<String, dynamic>();
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'id': 'chatcmpl-1',
          'object': 'chat.completion',
          'choices': [
            {
              'index': 0,
              'message': {'role': 'assistant', 'content': 'ok'},
              'finish_reason': 'stop',
            },
          ],
        }),
      );
      await request.response.close();
    });
    final chunks = await sendRequest(baseUrl);
    expect(chunks, isNotEmpty);
    expect(requestBody, isNotNull);
    return requestBody!;
  } finally {
    await server.close(force: true);
  }
}

Future<Map<String, dynamic>> _sendAndCaptureResponsesBody(
  Future<List<dynamic>> Function(String baseUrl) sendRequest,
) async {
  Map<String, dynamic>? requestBody;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final baseUrl = 'http://${server.address.address}:${server.port}/v1';
  try {
    server.listen((request) async {
      final rawBody = await utf8.decoder.bind(request).join();
      requestBody = (jsonDecode(rawBody) as Map).cast<String, dynamic>();
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'id': 'resp-1',
          'object': 'response',
          'status': 'completed',
          'output': [
            {
              'type': 'message',
              'role': 'assistant',
              'content': [
                {'type': 'output_text', 'text': 'ok'},
              ],
            },
          ],
        }),
      );
      await request.response.close();
    });
    final chunks = await sendRequest(baseUrl);
    expect(chunks, isNotEmpty);
    expect(requestBody, isNotNull);
    return requestBody!;
  } finally {
    await server.close(force: true);
  }
}
