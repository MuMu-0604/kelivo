import 'package:html/dom.dart' as dom;

import '../search_service.dart';

class LocalSearchResultFilter {
  LocalSearchResultFilter._();

  static final RegExp _spaceRe = RegExp(r'\s+');
  static final RegExp _trackingParamRe = RegExp(
    r'(^|[?&])(utm_[^=]*|spm|from|fr|src|source|campaign|track|tracking)=',
    caseSensitive: false,
  );
  static final RegExp _blockedUrlRe = RegExp(
    r'^(javascript:|#|mailto:|tel:|about:|data:)',
    caseSensitive: false,
  );
  static final RegExp _badHostRe = RegExp(
    r'(^|\.)('
    r'pos\.baidu\.com|cpro\.baidu\.com|eiv\.baidu\.com|union\.baidu\.com|wangmeng\.baidu\.com|tuiguang\.baidu\.com|eclick\.baidu\.com|epro\.sogou\.com|p4p\.sogou\.com|theta\.sogoucdn\.com|sax\.so\.com|s\.360\.cn|show\.360\.cn|ad\.so\.com'
    r')$',
    caseSensitive: false,
  );
  static final RegExp _adMarkerRe = RegExp(
    r'(广告|推广|商业推广|赞助| sponsored | sponsor |\bad\b|\bads\b|advert|promotion|promoted|p4p|ec_|cpro|tuiguang)',
    caseSensitive: false,
  );
  static final RegExp _navigationMarkerRe = RegExp(
    r'(相关搜索|大家还在搜|搜索历史|换一换|展开全部|收起|反馈|登录|app下载|打开APP|立即打开|download app)',
    caseSensitive: false,
  );

  static SearchResultItem? buildItem({
    required dom.Element block,
    required String title,
    required String url,
    required String snippet,
  }) {
    final cleanTitle = clean(title);
    final cleanUrl = url.trim();
    final cleanSnippet = clean(snippet);
    if (cleanTitle.isEmpty || cleanUrl.isEmpty) return null;
    if (_looksBlockedUrl(cleanUrl)) return null;
    if (_looksLikeAd(block, cleanTitle, cleanUrl, cleanSnippet)) return null;
    if (_looksLikeNavigation(block, cleanTitle, cleanSnippet)) return null;
    if (_looksLowValue(cleanTitle, cleanSnippet)) return null;
    return SearchResultItem(
      title: cleanTitle,
      url: cleanUrl,
      text: _trimSnippet(cleanSnippet, cleanTitle),
    );
  }

  static String clean(String value) {
    return value.replaceAll(_spaceRe, ' ').trim();
  }

  static List<SearchResultItem> dedupe(List<SearchResultItem> items) {
    final seen = <String>{};
    final out = <SearchResultItem>[];
    for (final item in items) {
      final key = _dedupeKey(item);
      if (key.isEmpty || !seen.add(key)) continue;
      out.add(item);
    }
    return out;
  }

  static bool _looksBlockedUrl(String url) {
    if (_blockedUrlRe.hasMatch(url)) return true;
    final parsed = Uri.tryParse(url);
    if (parsed == null) return false;
    final host = parsed.host.toLowerCase();
    if (host.isNotEmpty && _badHostRe.hasMatch(host)) return true;
    final path = parsed.path.toLowerCase();
    if (path.contains('/s?') || path == '/s' || path == '/web') return true;
    return false;
  }

  static bool _looksLikeAd(
    dom.Element block,
    String title,
    String url,
    String snippet,
  ) {
    final signals = <String>[
      block.localName ?? '',
      block.className,
      block.id,
      block.attributes.entries
          .where((entry) => entry.key.toString().startsWith('data-'))
          .map((entry) => '${entry.key}=${entry.value}')
          .join(' '),
      block.attributes['aria-label'] ?? '',
      title,
      snippet,
      url,
    ].join(' ').toLowerCase();
    return _adMarkerRe.hasMatch(signals);
  }

  static bool _looksLikeNavigation(
    dom.Element block,
    String title,
    String text,
  ) {
    final signals = '${block.className} ${block.id} $title $text';
    return _navigationMarkerRe.hasMatch(signals);
  }

  static bool _looksLowValue(String title, String snippet) {
    if (title.length < 2) return true;
    final normalizedTitle = title.toLowerCase();
    if (normalizedTitle == '百度一下' || normalizedTitle == 'sogou') return true;
    if (snippet.isEmpty && title.length < 6) return true;
    return false;
  }

  static String _trimSnippet(String snippet, String title) {
    if (snippet.startsWith(title)) {
      return clean(snippet.substring(title.length));
    }
    return snippet;
  }

  static String _dedupeKey(SearchResultItem item) {
    final parsed = Uri.tryParse(item.url.trim());
    if (parsed != null && parsed.host.isNotEmpty) {
      final query = Map<String, String>.from(parsed.queryParameters)
        ..removeWhere((key, value) => _trackingParamRe.hasMatch('?$key='));
      final base = parsed.replace(query: '').toString();
      if (query.isEmpty) return base;
      final sortedKeys = query.keys.toList()..sort();
      final normalizedQuery = sortedKeys
          .map((key) => '$key=${query[key]}')
          .join('&');
      return '$base?$normalizedQuery';
    }
    return item.title.trim().toLowerCase();
  }
}
