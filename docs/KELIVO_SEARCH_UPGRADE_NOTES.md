# Kelivo Search Upgrade Notes

This document summarizes the Local Hybrid Search upgrade included in Kelivo Plus.

## Goal

Kelivo Plus adds a practical API-key-free search mode for users who want online discovery without configuring commercial search providers. The implementation aggregates several local HTML-based search sources, then cleans and ranks results before sending them back to the model.

## Delivered Changes

- Added local Chinese search providers:
  - Baidu
  - Sogou
  - 360 Search
- Added Local Hybrid Search:
  - Bing Local
  - DuckDuckGo
  - Baidu
  - Sogou
  - 360 Search
- Added shared result cleanup and ranking:
  - URL normalization
  - tracking parameter removal
  - duplicate merging
  - low-value host filtering
  - provider/source weighting
- Registered Local Hybrid Search in app settings and search service creation.
- Added focused tests for provider serialization, parser behavior, filtering, and hybrid ranking.

## Architecture

- User-facing local search should prefer Local Hybrid Search rather than exposing Baidu, Sogou, or 360 as standalone entries.
- Provider-specific parsing belongs in each provider implementation.
- Shared filtering, deduplication, URL cleanup, and ranking rules belong in the local search result filter.
- Individual provider failures must not fail the whole hybrid search request.
- Chinese search sources are weighted as discovery sources and are especially useful for Chinese queries.

## Ranking Policy

Results are ranked by a combination of:

- provider weight
- original provider rank
- duplicate/source consensus
- trusted-domain boosts
- spam or low-value host penalties

Official documentation, government/education sites, GitHub, arXiv, PubMed/NIH, and developer documentation are treated as higher-trust sources. Ad-like pages, low-quality download/crack sites, SEO garbage, and tracking-heavy URLs are penalized or filtered.

## Verification

Focused tests cover Local Hybrid Search behavior and local Chinese providers. Search changes should be validated with targeted tests before release:

```powershell
flutter test test/core/services/search/hybrid_local_search_service_test.dart test/core/services/search/local_chinese_search_service_test.dart
```

## Future Work

- Add measured examples from real search results before expanding filter rules.
- Keep parser changes isolated by provider.
- Avoid requiring API keys for the Local Hybrid Search mode.
- Continue to expose paid/API providers separately for users who prefer those services.
