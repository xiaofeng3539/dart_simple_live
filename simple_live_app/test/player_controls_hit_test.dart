import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils/listen_fourth_button.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_controls.dart';

class _Settings extends AppSettingsController {
  // 测试不初始化持久化设置。
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
}

void main() {
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
        await tester.tap(find.byIcon(Icons.arrow_back));
        expect(room.exits, 1);
      }
      final point = tester.getCenter(find.byType(Scaffold));
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 80));
      expect(full ? room.exits : room.enters, full ? 2 : 1);
      await tester.pumpWidget(const SizedBox.shrink());
      room.hideControlsTimer?.cancel();
    });
  }
}
