import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/app/utils/listen_fourth_button.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_controls.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class _Settings extends AppSettingsController {
  // 测试不初始化持久化设置。
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _Follows extends FollowService {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _Stream implements PlayerStream {
  @override
  Stream<bool> get buffering => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements Player {
  @override
  PlayerState get state => const PlayerState();
  @override
  PlayerStream get stream => _Stream();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _VideoController implements VideoController {
  @override
  Player get player => _Player();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _VideoState with Diagnosticable implements VideoState {
  _VideoState(this.context);
  @override
  final BuildContext context;
  @override
  Video get widget => Video(controller: _VideoController());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room extends LiveRoomController {
  _Room() : super(pSite: Sites.allSites['huya']!, pRoomId: '1');
  int exits = 0;
  int refreshes = 0;
  int screenshots = 0;
  int enters = 0;
  int followSheets = 0;
  int settingSheets = 0;
  int qualitySheets = 0;
  int lineSheets = 0;
  int danmakuSheets = 0;
  @override
  Future<void> exitFull() async {
    exits++;
  }

  @override
  void refreshRoom() {
    refreshes++;
  }

  @override
  Future<void> saveScreenshot() async {
    screenshots++;
  }

  @override
  Future<void> enterFullScreen() async {
    enters++;
  }
  @override
  void showFollowUserSheet() => followSheets++;
  @override
  void showPlayerSettingsSheet() => settingSheets++;
  @override
  void showQualitySheet() => qualitySheets++;
  @override
  void showPlayUrlsSheet() => lineSheets++;
  @override
  void showDanmuSettingsSheet() => danmakuSheets++;
}

void main() {
  final buttons = <String, Finder Function()>{
    '关注列表': () => find.byIcon(Remix.play_list_2_line),
    '设置': () => find.byIcon(Icons.more_horiz),
    '清晰度': () => find.text('原画'),
    '线路': () => find.text('线路1'),
    '弹幕设置': () => find.byType(ImageIcon).last,
  };
  for (final button in buttons.entries) {
    testWidgets('全屏${button.key}按钮实际打开可见弹层', (tester) async {
      Get.put<FollowService>(_Follows());
      final room = _Room();
      room.fullScreenState.value = true;
      room.showControlsState.value = true;
      room.showDanmakuState.value = true;
      room.currentQualityInfo.value = '原画';
      room.currentLineInfo.value = '线路1';
      room.qualites.add(LivePlayQuality(quality: '原画', data: {}));
      room.playUrls.add('https://example.com/live.flv');
      await tester.pumpWidget(GetMaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        navigatorObservers: [FlutterSmartDialog.observer],
        builder: FlutterSmartDialog.init(),
        home: Scaffold(body: Builder(
          builder: (context) => buildFullControls(_VideoState(context), room),
        )),
      ));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(button.value());
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text(button.key), findsWidgets);
      SmartDialog.dismiss(status: SmartStatus.allCustom);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpWidget(const SizedBox.shrink());
      room.hideControlsTimer?.cancel();
    });
  }
  testWidgets('播放器右侧系统弹层在导航页上可见', (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      navigatorObservers: [FlutterSmartDialog.observer],
      builder: FlutterSmartDialog.init(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Utils.showRightDialog(
              title: '线路',
              useSystem: true,
              child: const Text('线路1'),
            ),
            child: const Text('打开线路'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开线路'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('线路1'), findsOneWidget);
  });
  testWidgets('播放器底部弹层在全屏页面可见', (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: PopScope(
        canPop: false,
        child: Scaffold(
          body: TextButton(
            onPressed: () => Utils.showBottomSheet(
              title: '切换线路',
              child: const Text('线路1'),
            ),
            child: const Text('打开线路'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开线路'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('线路1'), findsOneWidget);
  });
  test('鼠标侧键识别器不参与左键和触摸手势竞争', () {
    final recognizer = FourthButtonTapGestureRecognizer();
    expect(
        recognizer
            .isPointerAllowed(const PointerDownEvent(buttons: kPrimaryButton)),
        isFalse);
    expect(
        recognizer.isPointerAllowed(const PointerDownEvent(
            kind: PointerDeviceKind.mouse, buttons: kBackMouseButton)),
        isTrue);
    recognizer.dispose();
  });
  setUp(() {
    Get.put<AppSettingsController>(_Settings());
    AppSettingsController.instance.playershowSuperChat.value = false;
  });
  tearDown(() => Get.reset());
  testWidgets('第二次点击松开后才切换全屏，不在按下时重建播放区域', (tester) async {
    final room = _Room();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => buildControls(false, _VideoState(context), room),
    ))));
    final point = tester.getCenter(find.byType(Scaffold));
    await tester.tapAt(point, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 80));
    final gesture =
        await tester.startGesture(point, kind: PointerDeviceKind.mouse);
    expect(room.enters, 0);
    await gesture.up();
    expect(room.enters, 1);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    room.hideControlsTimer?.cancel();
  });
  for (final full in [false, true]) {
    testWidgets('${full ? "全屏" : "普通"}控制层不因同方向尺寸变化重新构造', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final room = _Room();
      room.fullScreenState.value = full;
      var builds = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
        builder: (context) {
          builds++;
          return playerControls(_VideoState(context), room);
        },
      ))));
      final initial = builds;
      for (var i = 1; i <= 20; i++) {
        tester.view.physicalSize = Size(1200 + i * 10, 800);
        await tester.pump();
      }
      debugPrint(
          '20 次 resize：${full ? "全屏" : "普通"}控制层构造 ${builds - initial} 次');
      expect(builds, initial);
      await tester.pumpWidget(const SizedBox.shrink());
      room.hideControlsTimer?.cancel();
    });
    testWidgets('${full ? "全屏" : "普通"}控件可点击且不触发画面手势', (tester) async {
      final room = _Room();
      room.fullScreenState.value = full;
      room.showControlsState.value = true;
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
              body: RawGestureDetector(
                  gestures: {
            FourthButtonTapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                    FourthButtonTapGestureRecognizer>(
              FourthButtonTapGestureRecognizer.new,
              (recognizer) => recognizer.onTapDown = (_) {},
            ),
          },
                  child: Builder(
                    builder: (context) => full
                        ? buildFullControls(_VideoState(context), room)
                        : buildControls(false, _VideoState(context), room),
                  )))));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byIcon(Remix.refresh_line));
      expect(room.refreshes, 1);
      expect(room.showControlsState.value, isTrue);
      if (full) {
        await tester.tap(find.byIcon(Icons.camera_alt_outlined));
        expect(room.screenshots, 1);
        await tester.tap(find.byIcon(Remix.fullscreen_exit_fill));
        expect(room.exits, 1);
        await tester.tap(find.byIcon(Icons.arrow_back));
        expect(room.exits, 2);
      }
      final point = tester.getCenter(find.byType(Scaffold));
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 80));
      expect(full ? room.exits : room.enters, full ? 3 : 1);
      await tester.pumpWidget(const SizedBox.shrink());
      room.hideControlsTimer?.cancel();
    });
  }
  testWidgets('竖屏全屏右上角和右下角按钮可点击', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1080, 1920);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final room = _Room();
    room.fullScreenState.value = true;
    room.showControlsState.value = true;
    room.showDanmakuState.value = true;
    room.isVertical.value = true;
    room.currentQualityInfo.value = '原画';
    room.currentLineInfo.value = '线路1';
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(body: Builder(
        builder: (context) => buildFullControls(_VideoState(context), room),
      )),
    ));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byIcon(Icons.camera_alt_outlined));
    expect(room.screenshots, 1);
    await tester.tap(find.byIcon(Remix.play_list_2_line));
    expect(room.followSheets, 1);
    await tester.tap(find.byIcon(Icons.more_horiz));
    expect(room.settingSheets, 1);
    await tester.tap(find.text('原画'));
    expect(room.qualitySheets, 1);
    await tester.tap(find.text('线路1'));
    expect(room.lineSheets, 1);
    await tester.tap(find.byType(ImageIcon).last);
    expect(room.danmakuSheets, 1);
    await tester.tap(find.byIcon(Remix.fullscreen_exit_fill));
    expect(room.exits, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    room.hideControlsTimer?.cancel();
  });
  testWidgets('切换为全屏并改变尺寸后，右侧按钮继续响应', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final room = _Room();
    room.showControlsState.value = true;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(body: Builder(
        builder: (context) => playerControls(_VideoState(context), room),
      )),
    ));
    room.fullScreenState.value = true;
    tester.view.physicalSize = const Size(1920, 1080);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byIcon(Icons.camera_alt_outlined));
    expect(room.screenshots, 1);
    await tester.tap(find.byIcon(Remix.fullscreen_exit_fill));
    expect(room.exits, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    room.hideControlsTimer?.cancel();
  });
}
