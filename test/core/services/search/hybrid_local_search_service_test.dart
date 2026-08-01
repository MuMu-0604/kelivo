import 'package:Kelivo/core/services/search/providers/hybrid_local_search_service.dart';
import 'package:Kelivo/core/services/search/search_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeService<T extends SearchServiceOptions> extends SearchService<T> {
  _FakeService(this._result, {this.shouldThrow = false});

  final SearchResult _result;
  final bool shouldThrow;

  @override
  String get name => 'fake';

  @override
  Widget description(BuildContext context) => const SizedBox.shrink();

  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required T serviceOptions,
  }) async {
    if (shouldThrow) throw Exception('boom');
    return _result;
  }
}

void main() {
  group('HybridLocalSearchService', () {
    test('serializes options and resolves factory service', () {
      final options = HybridLocalSearchOptions(
        id: 'hybrid-1',
        mode: HybridLocalSearchMode.chinese,
        providers: const [HybridLocalProvider.bing, HybridLocalProvider.baidu],
        maxResultsPerProvider: 3,
        timeoutPerProviderMs: 1200,
        duckDuckGoRegion: 'cn-zh',
      );

      final restored = SearchServiceOptions.fromJson(options.toJson());

      expect(restored, isA<HybridLocalSearchOptions>());
      final hybrid = restored as HybridLocalSearchOptions;
      expect(hybrid.id, 'hybrid-1');
      expect(hybrid.mode, HybridLocalSearchMode.chinese);
      expect(hybrid.providers, [
        HybridLocalProvider.bing,
        HybridLocalProvider.baidu,
      ]);
      expect(hybrid.maxResultsPerProvider, 3);
      expect(hybrid.timeoutPerProviderMs, 1200);
      expect(hybrid.duckDuckGoRegion, 'cn-zh');
      expect(
        SearchService.getService(options),
        isA<HybridLocalSearchService>(),
      );
    });

    test(
      'merges sources, ignores failed providers, and dedupes URLs',
      () async {
        final service = HybridLocalSearchService(
          bing: _FakeService<BingLocalOptions>(
            SearchResult(
              items: [
                SearchResultItem(
                  title: 'Official Docs',
                  url: 'https://docs.example.com/a?utm_source=bing',
                  text: 'Docs result',
                ),
              ],
            ),
          ),
          duckDuckGo: _FakeService<DuckDuckGoOptions>(
            SearchResult(
              items: [
                SearchResultItem(
                  title: 'Official Docs Duplicate',
                  url: 'https://docs.example.com/a',
                  text: 'Duplicate result',
                ),
              ],
            ),
          ),
          baidu: _FakeService<BaiduLocalOptions>(
            SearchResult(
              items: [
                SearchResultItem(
                  title: 'Low Value Download',
                  url: 'https://download.example.com/crack',
                  text: 'download crack',
                ),
              ],
            ),
          ),
          sogou: _FakeService<SogouLocalOptions>(
            SearchResult(items: const []),
            shouldThrow: true,
          ),
          so360: _FakeService<So360LocalOptions>(
            SearchResult(
              items: [
                SearchResultItem(
                  title: 'GitHub Repo',
                  url: 'https://github.com/example/repo',
                  text: 'Repository',
                ),
              ],
            ),
          ),
        );

        final result = await service.search(
          query: '中文 kelivo',
          commonOptions: const SearchCommonOptions(
            resultSize: 10,
            timeout: 1000,
          ),
          serviceOptions: HybridLocalSearchOptions(
            id: 'hybrid-1',
            mode: HybridLocalSearchMode.chinese,
          ),
        );

        expect(result.items.map((e) => e.url), [
          'https://docs.example.com/a?utm_source=bing',
          'https://github.com/example/repo',
          'https://download.example.com/crack',
        ]);
      },
    );
  });
}
