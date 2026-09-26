import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/search_controller.dart';

void main() {
  test('四个平台进入直播间时各提示一次', () {
    final controller = AppSearchController();
    final prompts = <String>[];
    controller.onRoomDetected = prompts.add;
    const rooms = [
      (Constant.kBiliBili, 'https://live.bilibili.com/12345', '12345'),
      (Constant.kHuya, 'https://www.huya.com/abc123', 'abc123'),
      (Constant.kDouyu, 'https://www.douyu.com/67890', '67890'),
      (
        Constant.kDouyin,
        'https://live.douyin.com/921169302662?enter_from_merge=web_live',
        '921169302662'
      ),
    ];
    for (final (siteId, url, roomId) in rooms) {
      controller.selectSite(Sites.allSites[siteId]!);
      controller.updateUrl(Uri.parse(url));
      controller.updateUrl(Uri.parse(url));
      expect(prompts.last, roomId);
    }
    expect(prompts.length, rooms.length);
  });

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
