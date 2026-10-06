import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_page.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/filter_button.dart';
import 'package:simple_live_app/widgets/follow_user_item.dart';

class _Service extends FollowService {
  // 测试使用内存数据，不启动定时器或请求网络。
  @override
  // ignore: must_call_super
  void onInit() {}
  @override
  Future<void> loadData({bool updateStatus = true}) async {}
}

class _Controller extends FollowUserController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

FollowUser user(String name, String? category, int status) {
  final item = FollowUser.fromJson({
    'id': 'huya_$name', 'roomId': name, 'siteId': 'huya',
    'userName': name, 'face': '', 'addTime': '2026-10-06T00:00:00',
    'categoryName': category,
  });
  item.liveStatus.value = status;
  return item;
}

void main() {
  late _Controller controller;
  setUp(() {
    final service = Get.put<FollowService>(_Service());
    final users = [user('联盟一', '英雄联盟', 2), user('契约一', '无畏契约', 2),
      user('联盟二', ' 英雄联盟 ', 1), user('未知', null, 1)];
    service.followList.assignAll(users);
    service.liveList.assignAll(users.where((item) => item.liveStatus.value == 2));
    service.notLiveList.assignAll(users.where((item) => item.liveStatus.value == 1));
    controller = _Controller();
    controller.list.assignAll(users);
    Get.put<FollowUserController>(controller);
  });
  tearDown(() => Get.reset());

  Future<void> show(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const GetMaterialApp(home: FollowUserPage()));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('相同游戏合并并保持组内顺序，未知分类归其他，复用原主播卡片', (tester) async {
    await show(tester, const Size(2200, 1200));
    expect(find.text('英雄联盟 2人'), findsOneWidget);
    expect(find.text('无畏契约 1人'), findsOneWidget);
    expect(find.text('其他 1人'), findsOneWidget);
    final cards = tester.widgetList<FollowUserItem>(find.byType(FollowUserItem)).toList();
    expect(cards.map((item) => item.item.userName), ['联盟一', '联盟二', '契约一', '未知']);
    for (final item in cards) {
      expect(item.onTap, isNotNull);
      expect(item.onRemove, isNotNull);
      expect(item.onLongPress, isNotNull);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('先用原顶部筛选过滤，再计算分组人数，窄窗口无溢出', (tester) async {
    await show(tester, const Size(400, 1000));
    await tester.tap(find.widgetWithText(FilterButton, '直播中'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('英雄联盟 1人'), findsOneWidget);
    expect(find.text('无畏契约 1人'), findsOneWidget);
    expect(find.text('其他 1人'), findsNothing);
    expect(find.byType(FollowUserItem), findsNWidgets(2));
    await tester.tap(find.widgetWithText(FilterButton, '未开播'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('英雄联盟 1人'), findsOneWidget);
    expect(find.text('其他 1人'), findsOneWidget);
    expect(find.text('无畏契约 1人'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Windows字体下分类长列表可连续滚轮到底，底部不回跳', (tester) async {
    final fontFile = File('C:/Windows/Fonts/msyh.ttc');
    final font = FontLoader('Microsoft YaHei');
    font.addFont(Future.value(ByteData.sublistView(fontFile.readAsBytesSync())));
    await font.load();
    final users = List.generate(76, (i) =>
        user('主播$i${i % 5 == 0 ? '（较长的名称与直播内容）' : ''}', '游戏${i ~/ 7}', i.isEven ? 2 : 1));
    final service = Get.find<FollowService>();
    service.followList.assignAll(users);
    controller.list.assignAll(users);
    await tester.binding.setSurfaceSize(const Size(2048, 1195));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(GetMaterialApp(
      theme: ThemeData(fontFamily: 'Microsoft YaHei'),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(2048, 1195), textScaler: TextScaler.linear(1.25)),
        child: const FollowUserPage(),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    double previous = 0;
    for (var i = 0; i < 100; i++) {
      await tester.sendEventToBinding(const PointerScrollEvent(
        position: Offset(1000, 600), scrollDelta: Offset(0, 80), kind: PointerDeviceKind.mouse));
      await tester.pump(const Duration(milliseconds: 100));
      final position = controller.scrollController.position;
      expect(position.pixels, greaterThanOrEqualTo(previous - 0.01));
      previous = position.pixels;
    }
    expect(controller.scrollController.position.extentAfter, closeTo(0, 0.01));
    final last = find.byWidgetPredicate((widget) => widget is FollowUserItem && widget.item.id == users.last.id);
    expect(last, findsOneWidget);
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(1195));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }, skip: !File('C:/Windows/Fonts/msyh.ttc').existsSync());
}
