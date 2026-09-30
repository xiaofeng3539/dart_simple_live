import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_controls.dart';
import 'package:window_manager/window_manager.dart';

class _TestPlayer
    with PlayerMixin, PlayerStateMixin, PlayerDanmakuMixin, PlayerSystemMixin {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> calls;
  var maximized = false;

  setUp(() {
    calls = [];
    maximized = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'isMaximized') return maximized;
      if (call.method == 'unmaximize') {
        Future<void>.delayed(const Duration(milliseconds: 20), () {
          maximized = false;
        });
      }
      if (call.method == 'setFullScreen' &&
          call.arguments['isFullScreen'] == true &&
          maximized) {
        throw PlatformException(code: 'window-still-maximized');
      }
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Windows 原生全屏完成前保持原页面布局', () async {
    final fullscreenComplete = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isMaximized') return false;
      if (call.method == 'setFullScreen') await fullscreenComplete.future;
      return null;
    });
    final controller = _TestPlayer();

    final entering = controller.enterFullScreen();
    await Future<void>.delayed(Duration.zero);
    expect(controller.fullScreenState.value, isFalse);

    fullscreenComplete.complete();
    await entering;
    expect(controller.fullScreenState.value, isTrue);
  });

  testWidgets('普通全屏画面不拖动窗口，小窗仍能拖动', (tester) async {
    const content = SizedBox(key: ValueKey('player'));
    await tester.pumpWidget(MaterialApp(
      home: playerWindowDragArea(child: content, isSmallWindow: false),
    ));
    expect(find.byType(DragToMoveArea), findsNothing);

    await tester.pumpWidget(MaterialApp(
      home: playerWindowDragArea(child: content, isSmallWindow: true),
    ));
    expect(find.byType(DragToMoveArea), findsOneWidget);
  });

  test('已最大化窗口进入全屏时先还原，退出时恢复最大化', () async {
    maximized = true;
    final controller = _TestPlayer();

    await controller.enterFullScreen();
    expect(controller.fullScreenState.value, isTrue);
    expect(calls.first, 'isMaximized');
    expect(calls, contains('unmaximize'));
    expect(calls.last, 'setFullScreen');

    calls.clear();
    await controller.exitFull();
    expect(controller.fullScreenState.value, isFalse);
    expect(calls, ['setFullScreen', 'setTitleBarStyle', 'maximize']);
  });

  test('普通窗口全屏退出后保持普通窗口', () async {
    final controller = _TestPlayer();

    await controller.enterFullScreen();
    expect(calls, ['isMaximized', 'setFullScreen']);

    calls.clear();
    await controller.exitFull();
    expect(calls, ['setFullScreen', 'setTitleBarStyle']);
  });

  test('小窗退出恢复窗口，不走普通全屏退出', () async {
    final controller = _TestPlayer();
    controller.smallWindowState.value = true;
    controller.fullScreenState.value = true;

    await controller.exitFull();

    expect(controller.smallWindowState.value, isFalse);
    expect(controller.fullScreenState.value, isFalse);
    expect(calls, ['setTitleBarStyle', 'setAlwaysOnTop']);
  });
}
