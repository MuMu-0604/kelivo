import 'dart:async';

import 'package:flutter/material.dart';

import '../search_service.dart';
import 'baidu_search_service.dart';
import 'bing_search_service.dart';
import 'duckduckgo_search_service.dart';
import 'so360_search_service.dart';
import 'sogou_search_service.dart';

class HybridLocalSearchService extends SearchService<HybridLocalSearchOptions> {
  HybridLocalSearchService({
    SearchService<BingLocalOptions>? bing,
    SearchService<DuckDuckGoOptions>? duckDuckGo,
    SearchService<BaiduLocalOptions>? baidu,
    SearchService<SogouLocalOptions>? sogou,
    SearchService<So360LocalOptions>? so360,
  }) : _bing = bing ?? BingSearchService(),
       _duckDuckGo = duckDuckGo ?? DuckDuckGoSearchService(),
       _baidu = baidu ?? BaiduSearchService(),
       _sogou = sogou ?? SogouSearchService(),
       _so360 = so360 ?? So360SearchService();

  final SearchService<BingLocalOptions> _bing;
  final SearchService<DuckDuckGoOptions> _duckDuckGo;
  final SearchService<BaiduLocalOptions> _baidu;
  final SearchService<SogouLocalOptions> _sogou;
  final SearchService<So360LocalOptions> _so360;

  @override
  String get name => 'Local Hybrid Search';

  @override
  Widget description(BuildContext context) {
    return const Text(
      'Runs multiple local HTML search engines without API keys, then filters, deduplicates, and ranks results by source quality.',
      style: TextStyle(fontSize: 12),
    );
  }

  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required HybridLocalSearchOptions serviceOptions,
  }) async {
    final providers = serviceOptions.enabledProviders;
    final timeoutMs = serviceOptions.timeoutPerProviderMs > 0
        ? serviceOptions.timeoutPerProviderMs
        : commonOptions.timeout;
    final perProviderSize = serviceOptions.maxResultsPerProvider.clamp(
      1,
      commonOptions.resultSize,
    );
    final perProviderCommon = SearchCommonOptions(
      resultSize: perProviderSize,
      timeout: timeoutMs,
    );

    final tasks = <Future<List<_ScoredSearchItem>>>[];
    if (providers.contains(HybridLocalProvider.bing)) {
      tasks.add(
        _runProvider(
          provider: HybridLocalProvider.bing,
          weight: 1.0,
          search: () => _bing.search(
            query: query,
            commonOptions: perProviderCommon,
            serviceOptions: BingLocalOptions(id: '${serviceOptions.id}-bing'),
          ),
        ),
      );
    }
    if (providers.contains(HybridLocalProvider.duckduckgo)) {
      tasks.add(
        _runProvider(
          provider: HybridLocalProvider.duckduckgo,
          weight: 0.75,
          search: () => _duckDuckGo.search(
            query: query,
            commonOptions: perProviderCommon,
            serviceOptions: DuckDuckGoOptions(
              id: '${serviceOptions.id}-duckduckgo',
              region: serviceOptions.duckDuckGoRegion,
            ),
          ),
        ),
      );
    }
    if (_shouldUseChineseProviders(query, serviceOptions)) {
      if (providers.contains(HybridLocalProvider.baidu)) {
        tasks.add(
          _runProvider(
            provider: HybridLocalProvider.baidu,
            weight: 0.45,
            search: () => _baidu.search(
              query: query,
              commonOptions: perProviderCommon,
              serviceOptions: BaiduLocalOptions(
                id: '${serviceOptions.id}-baidu',
              ),
            ),
          ),
        );
      }
      if (providers.contains(HybridLocalProvider.sogou)) {
        tasks.add(
          _runProvider(
            provider: HybridLocalProvider.sogou,
            weight: 0.40,
            search: () => _sogou.search(
              query: query,
              commonOptions: perProviderCommon,
              serviceOptions: SogouLocalOptions(
                id: '${serviceOptions.id}-sogou',
              ),
            ),
          ),
        );
      }
      if (providers.contains(HybridLocalProvider.so360)) {
        tasks.add(
          _runProvider(
            provider: HybridLocalProvider.so360,
            weight: 0.40,
            search: () => _so360.search(
              query: query,
              commonOptions: perProviderCommon,
              serviceOptions: So360LocalOptions(
                id: '${serviceOptions.id}-so360',
              ),
            ),
          ),
        );
      }
    }

    if (tasks.isEmpty) return SearchResult(items: const []);

    final settled = await Future.wait(tasks);
    final ranked = _rankAndDedupe(settled.expand((items) => items).toList());
    return SearchResult(
      items: ranked.take(commonOptions.resultSize).map((e) => e.item).toList(),
    );
  }

  Future<List<_ScoredSearchItem>> _runProvider({
    required HybridLocalProvider provider,
    required double weight,
    required Future<SearchResult> Function() search,
  }) async {
    try {
      final result = await search();
      return result.items.asMap().entries.map((entry) {
        final rankScore = 1.0 / (entry.key + 1);
        final item = entry.value;
        final trust = _domainTrustScore(item.url);
        final spamPenalty = _spamPenalty(item);
        return _ScoredSearchItem(
          item: item,
          provider: provider,
          score: weight + rankScore + trust - spamPenalty,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  List<_ScoredSearchItem> _rankAndDedupe(List<_ScoredSearchItem> items) {
    final buckets = <String, _ScoredSearchItem>{};
    for (final scored in items) {
      final key = _dedupeKey(scored.item);
      if (key.isEmpty) continue;
      final existing = buckets[key];
      if (existing == null) {
        buckets[key] = scored;
      } else {
        buckets[key] = existing.merge(scored);
      }
    }
    final out = buckets.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  bool _shouldUseChineseProviders(
    String query,
    HybridLocalSearchOptions options,
  ) {
    if (options.mode == HybridLocalSearchMode.chinese) return true;
    if (options.mode == HybridLocalSearchMode.fast) return false;
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(query);
  }

  double _domainTrustScore(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return 0;
    if (host.endsWith('.gov') || host.endsWith('.gov.cn')) return 1.2;
    if (host.endsWith('.edu') || host.endsWith('.edu.cn')) return 0.8;
    if (host == 'github.com' || host.endsWith('.github.com')) return 0.7;
    if (host.contains('docs.') || host.contains('developer.')) return 0.65;
    if (host == 'arxiv.org' || host.endsWith('.arxiv.org')) return 0.75;
    if (host == 'pubmed.ncbi.nlm.nih.gov' || host.endsWith('.nih.gov')) {
      return 0.9;
    }
    if (host.endsWith('.org')) return 0.25;
    if (_aggregatorHostRe.hasMatch(host)) return -0.8;
    return 0;
  }

  double _spamPenalty(SearchResultItem item) {
    final signal = '${item.title} ${item.url} ${item.text}'.toLowerCase();
    if (_spamSignalRe.hasMatch(signal)) return 0.9;
    return 0;
  }

  String _dedupeKey(SearchResultItem item) {
    final parsed = Uri.tryParse(item.url.trim());
    if (parsed == null || parsed.host.isEmpty) {
      return item.title.trim().toLowerCase();
    }
    final query = Map<String, String>.from(parsed.queryParameters)
      ..removeWhere((key, value) => _trackingParamRe.hasMatch(key));
    final normalized = query.isEmpty
        ? parsed.replace(fragment: '', query: '')
        : parsed.replace(fragment: '', queryParameters: query);
    return '${normalized.host.toLowerCase()}${normalized.path}${normalized.hasQuery ? '?${normalized.query}' : ''}';
  }

  static final RegExp _trackingParamRe = RegExp(
    r'^(utm_|spm$|from$|fr$|src$|source$|campaign$|track|tracking)',
    caseSensitive: false,
  );
  static final RegExp _aggregatorHostRe = RegExp(
    r'(^|\.)(baijiahao\.baidu\.com|sohu\.com|hao123\.com|docin\.com|csdn\.net)$',
    caseSensitive: false,
  );
  static final RegExp _spamSignalRe = RegExp(
    r'(下载站|破解版|绿色版|广告|推广|招商|加盟|seo|采集|mirror site|download crack)',
    caseSensitive: false,
  );
}

class _ScoredSearchItem {
  const _ScoredSearchItem({
    required this.item,
    required this.provider,
    required this.score,
  });

  final SearchResultItem item;
  final HybridLocalProvider provider;
  final double score;

  _ScoredSearchItem merge(_ScoredSearchItem other) {
    final best = other.score > score ? other : this;
    return _ScoredSearchItem(
      item: best.item,
      provider: best.provider,
      score: score + other.score + 0.3,
    );
  }
}
