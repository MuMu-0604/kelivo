import 'package:flutter/material.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;

import '../search_service.dart';
import 'local_search_result_filter.dart';

class SogouSearchService extends SearchService<SogouLocalOptions> {
  SogouSearchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  String get name => 'Sogou (Local)';

  @override
  Widget description(BuildContext context) {
    return const Text(
      'Uses local web scraping to fetch Sogou results. No API key required; availability may vary by network.',
      style: TextStyle(fontSize: 12),
    );
  }

  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required SogouLocalOptions serviceOptions,
  }) async {
    try {
      final uri = Uri.https('www.sogou.com', '/web', {
        'query': query,
        if (serviceOptions.page > 1) 'page': serviceOptions.page.toString(),
      });
      final response = await _client
          .get(uri, headers: _headers(serviceOptions.acceptLanguage))
          .timeout(Duration(milliseconds: commonOptions.timeout));

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch results: ${response.statusCode}');
      }

      final document = parser.parse(response.body);
      final blocks = document.querySelectorAll(
        '.vrwrap, .rb, .results > div, div[class*="result"], div[class*="vr"]',
      );
      final items = <SearchResultItem>[];
      for (final block in blocks) {
        if (items.length >= commonOptions.resultSize) break;
        final link = block.querySelector('h3 a, .pt a, a[href]');
        final href = link?.attributes['href']?.trim() ?? '';
        final title = link?.text ?? block.querySelector('h3')?.text ?? '';
        final snippet =
            block
                .querySelector('.str_info, .text-layout, .ft, .fz-mid, p')
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
      throw Exception('Sogou search failed: $e');
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
