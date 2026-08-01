import 'package:Kelivo/core/services/search/providers/baidu_search_service.dart';
import 'package:Kelivo/core/services/search/providers/so360_search_service.dart';
import 'package:Kelivo/core/services/search/providers/sogou_search_service.dart';
import 'package:Kelivo/core/services/search/search_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('local Chinese search providers', () {
    test('serialize options and resolve factory services', () {
      final cases = <SearchServiceOptions>[
        BaiduLocalOptions(id: 'baidu-1'),
        SogouLocalOptions(id: 'sogou-1'),
        So360LocalOptions(id: 'so360-1'),
      ];

      for (final options in cases) {
        final restored = SearchServiceOptions.fromJson(options.toJson());
        expect(restored.runtimeType, options.runtimeType);
        expect(restored.id, options.id);
      }

      expect(
        SearchService.getService(BaiduLocalOptions(id: 'baidu-1')),
        isA<BaiduSearchService>(),
      );
      expect(
        SearchService.getService(SogouLocalOptions(id: 'sogou-1')),
        isA<SogouSearchService>(),
      );
      expect(
        SearchService.getService(So360LocalOptions(id: 'so360-1')),
        isA<So360SearchService>(),
      );
    });

    test('Baidu parser extracts result cards', () async {
      final service = BaiduSearchService(
        client: MockClient(
          (_) async => http.Response('''
            <html><body>
              <div class="result"><h3><a href="https://example.com/a">Title A</a></h3><div class="c-abstract">Summary A</div></div>
              <div class="result"><h3><a href="https://example.com/b">Title B</a></h3><div class="c-abstract">Summary B</div></div>
            </body></html>
            ''', 200),
        ),
      );

      final result = await service.search(
        query: 'kelivo',
        commonOptions: const SearchCommonOptions(resultSize: 1, timeout: 1000),
        serviceOptions: BaiduLocalOptions(id: 'baidu-1'),
      );

      expect(result.items, hasLength(1));
      expect(result.items.single.title, 'Title A');
      expect(result.items.single.url, 'https://example.com/a');
      expect(result.items.single.text, 'Summary A');
    });

    test('Baidu parser filters ad-like and duplicate cards', () async {
      final service = BaiduSearchService(
        client: MockClient(
          (_) async => http.Response('''
            <html><body>
              <div class="result ad"><h3><a href="https://ad.example.com/a">Sponsored A</a></h3><div class="c-abstract">advert promotion</div></div>
              <div class="result"><h3><a href="https://example.com/a?utm_source=baidu">Title A</a></h3><div class="c-abstract">Summary A</div></div>
              <div class="result"><h3><a href="https://example.com/a">Title A duplicate</a></h3><div class="c-abstract">Summary duplicate</div></div>
              <div class="result"><h3><a href="javascript:void(0)">Bad Link</a></h3><div class="c-abstract">Summary Bad</div></div>
            </body></html>
            ''', 200),
        ),
      );

      final result = await service.search(
        query: 'kelivo',
        commonOptions: const SearchCommonOptions(resultSize: 10, timeout: 1000),
        serviceOptions: BaiduLocalOptions(id: 'baidu-1'),
      );

      expect(result.items, hasLength(1));
      expect(result.items.single.title, 'Title A');
      expect(result.items.single.url, 'https://example.com/a?utm_source=baidu');
    });

    test('Sogou parser extracts result cards', () async {
      final service = SogouSearchService(
        client: MockClient(
          (_) async => http.Response('''
            <html><body>
              <div class="vrwrap"><h3><a href="https://example.com/a">Title A</a></h3><p class="str_info">Summary A</p></div>
              <div class="vrwrap"><h3><a href="https://example.com/b">Title B</a></h3><p class="str_info">Summary B</p></div>
            </body></html>
            ''', 200),
        ),
      );

      final result = await service.search(
        query: 'kelivo',
        commonOptions: const SearchCommonOptions(resultSize: 2, timeout: 1000),
        serviceOptions: SogouLocalOptions(id: 'sogou-1'),
      );

      expect(result.items, hasLength(2));
      expect(result.items.first.title, 'Title A');
      expect(result.items.first.url, 'https://example.com/a');
      expect(result.items.first.text, 'Summary A');
    });

    test('Sogou parser filters promotion cards', () async {
      final service = SogouSearchService(
        client: MockClient(
          (_) async => http.Response('''
            <html><body>
              <div class="vrwrap p4p"><h3><a href="https://ad.example.com/a">Ad A</a></h3><p class="str_info">Sponsored result</p></div>
              <div class="vrwrap"><h3><a href="https://example.com/a">Title A</a></h3><p class="str_info">Summary A</p></div>
            </body></html>
            ''', 200),
        ),
      );

      final result = await service.search(
        query: 'kelivo',
        commonOptions: const SearchCommonOptions(resultSize: 10, timeout: 1000),
        serviceOptions: SogouLocalOptions(id: 'sogou-1'),
      );

      expect(result.items, hasLength(1));
      expect(result.items.single.title, 'Title A');
    });

    test('360 parser extracts result cards', () async {
      final service = So360SearchService(
        client: MockClient(
          (_) async => http.Response('''
            <html><body>
              <div class="res-list"><h3><a href="https://example.com/a">Title A</a></h3><p class="res-desc">Summary A</p></div>
              <div class="res-list"><h3><a href="https://example.com/b">Title B</a></h3><p class="res-desc">Summary B</p></div>
            </body></html>
            ''', 200),
        ),
      );

      final result = await service.search(
        query: 'kelivo',
        commonOptions: const SearchCommonOptions(resultSize: 2, timeout: 1000),
        serviceOptions: So360LocalOptions(id: 'so360-1'),
      );

      expect(result.items, hasLength(2));
      expect(result.items.first.title, 'Title A');
      expect(result.items.first.url, 'https://example.com/a');
      expect(result.items.first.text, 'Summary A');
    });

    test('360 parser filters ad-like cards', () async {
      final service = So360SearchService(
        client: MockClient(
          (_) async => http.Response('''
            <html><body>
              <div class="res-list ad"><h3><a href="https://ad.example.com/a">Ad A</a></h3><p class="res-desc">advert</p></div>
              <div class="res-list"><h3><a href="https://example.com/a">Title A</a></h3><p class="res-desc">Summary A</p></div>
            </body></html>
            ''', 200),
        ),
      );

      final result = await service.search(
        query: 'kelivo',
        commonOptions: const SearchCommonOptions(resultSize: 10, timeout: 1000),
        serviceOptions: So360LocalOptions(id: 'so360-1'),
      );

      expect(result.items, hasLength(1));
      expect(result.items.single.title, 'Title A');
    });
  });
}
