import 'package:flutter/material.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;

import '../search_service.dart';
import 'local_search_result_filter.dart';

class BaiduSearchService extends SearchService<BaiduLocalOptions> {
  BaiduSearchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  String get name => 'Baidu (Local)';

  @override
  Widget description(BuildContext context) {
    return const Text(
      'Uses local web scraping to fetch Baidu results. No API key required; availability may vary by network.',
      style: TextStyle(fontSize: 12),
    );
  }

  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required BaiduLocalOptions serviceOptions,
  }) async {
    try {
      final uri = Uri.https('www.baidu.com', '/s', {
        'wd': query,
        if (serviceOptions.pn > 0) 'pn': serviceOptions.pn.toString(),
      });
      final response = await _client
          .get(uri, headers: _headers(serviceOptions.acceptLanguage))
          .timeout(Duration(milliseconds: commonOptions.timeout));

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch results: ${response.statusCode}');
      }

      final document = parser.parse(response.body);
      final items = <SearchResultItem>[];
      final blocks = document.querySelectorAll(
        '.result, .result-op, [tpl], div[class*="result"]',
      );

      for (final block in blocks) {
        if (items.length >= commonOptions.resultSize) break;
        final link = block.querySelector('h3 a, .t a, a[href]');
        final href = link?.attributes['href']?.trim() ?? '';
        final title = link?.text ?? block.querySelector('h3')?.text ?? '';

        final snippet =
            block
                .querySelector(
                  '.c-abstract, .content-right_8Zs40, .c-span-last',
                )
                ?.text ??
            block.text;
        final item = LocalSearchResultFilter.buildItem(
          block: block,
          title: title,
          url: href,
          snippet: snippet,
        );
        if (item != null) items.add(item);
      }

      return SearchResult(items: LocalSearchResultFilter.dedupe(items));
    } catch (e) {
      throw Exception('Baidu search failed: $e');
    }
  }
}

Map<String, String> _headers(String acceptLanguage) => {
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
  'Accept':
      'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
  'Accept-Language': acceptLanguage.trim().isEmpty
      ? 'zh-CN,zh;q=0.9,en;q=0.8'
      : acceptLanguage.trim(),
};
