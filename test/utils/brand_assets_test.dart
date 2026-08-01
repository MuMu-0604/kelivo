import 'package:Kelivo/utils/brand_assets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BrandAssets', () {
    test('mapped Metaso icon is selectable as a built-in provider avatar', () {
      final asset = BrandAssets.assetForName('metaso');

      expect(asset, 'assets/icons/metaso-color.svg');
      expect(BrandAssets.selectableAssetOrNull(asset!), asset);
    });

    test('maps local Chinese search provider icons', () {
      final baidu = BrandAssets.assetForName('Baidu (Local)');
      final sogou = BrandAssets.assetForName('Sogou (Local)');
      final so360 = BrandAssets.assetForName('360 Search (Local)');

      expect(baidu, 'assets/icons/baidu-color.svg');
      expect(sogou, 'assets/icons/sogou-color.svg');
      expect(so360, 'assets/icons/so360-color.svg');
      expect(BrandAssets.selectableAssetOrNull(baidu!), baidu);
      expect(BrandAssets.selectableAssetOrNull(sogou!), sogou);
      expect(BrandAssets.selectableAssetOrNull(so360!), so360);
    });
  });
}
