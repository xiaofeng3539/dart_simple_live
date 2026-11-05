import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/search_controller.dart';

void main() {
  test('主页面导航提前识别房间，子资源不能覆盖跳转目标', () {
    final controller = AppSearchController();
    addTearDown(controller.onClose);
    controller.selectSite(Sites.allSites[Constant.kHuya]!);
    final prompts = <String>[];
    controller.onRoomDetected = prompts.add;
    final policy = controller.handleNavigation(NavigationAction(
      request: URLRequest(url: WebUri('https://m.huya.com/12345')),
      isForMainFrame: true,
    ));
    expect(policy, NavigationActionPolicy.ALLOW);
    controller.handleNavigation(NavigationAction(
      request: URLRequest(url: WebUri('https://example.com/ad')),
      isForMainFrame: false,
    ));
    expect(controller.roomId.value, '12345');
    expect(prompts, ['12345']);
  });

  test('四个平台手机导航都能产生房间提示和底部按钮目标', () {
    const cases = [
      (Constant.kBiliBili, 'https://live.bilibili.com/h5/12345', '12345'),
      (Constant.kHuya, 'https://m.huya.com/abc123', 'abc123'),
      (Constant.kDouyu, 'https://m.douyu.com/67890', '67890'),
      (
        Constant.kDouyin,
        'https://www.douyin.com/root/live/921169302662',
        '921169302662'
      ),
    ];
    for (final (site, url, id) in cases) {
      final controller = AppSearchController();
      addTearDown(controller.onClose);
      controller.selectSite(Sites.allSites[site]!);
      final prompts = <String>[];
      controller.onRoomDetected = prompts.add;
      controller.updateUrl(Uri.parse(url));
      controller.updateUrl(Uri.parse(url));
      expect(controller.roomId.value, id);
      expect(prompts, [id]);
    }
  });

  test('离开房间返回搜索页后再次进入同一房间仍提示', () {
    final controller = AppSearchController();
    addTearDown(controller.onClose);
    controller.selectSite(Sites.allSites[Constant.kDouyu]!);
    final prompts = <String>[];
    controller.onRoomDetected = prompts.add;
    controller.updateUrl(Uri.parse('https://www.douyu.com/12345'));
    controller.updateUrl(Uri.parse('https://www.douyu.com/search/abc'));
    controller.updateUrl(Uri.parse('https://www.douyu.com/12345'));
    expect(prompts, ['12345', '12345']);
  });

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
