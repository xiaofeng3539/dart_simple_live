import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/search_controller.dart';

void main() {
  test('选择平台后，仅在当前平台直播间显示跳转目标', () {
    final controller = AppSearchController();
    final site = Sites.allSites[Constant.kDouyu]!;

    controller.selectSite(site);
    expect(controller.selectedSite.value, site);
    expect(controller.roomId.value, isNull);

    controller.updateUrl(Uri.parse('https://www.douyu.com/12345'));
    expect(controller.roomId.value, '12345');

    controller.updateUrl(Uri.parse('https://www.douyu.com/search/abc'));
    expect(controller.roomId.value, isNull);

    controller.reset();
    expect(controller.selectedSite.value, isNull);
  });
}
