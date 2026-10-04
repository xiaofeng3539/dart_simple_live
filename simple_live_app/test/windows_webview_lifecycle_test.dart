import 'dart:async';

import 'package:flutter/services.dart';
// 直接验证项目内 Windows 插件的生命周期。
// ignore: depend_on_referenced_packages
import 'package:flutter_inappwebview_windows/src/in_app_webview/custom_platform_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel =
      MethodChannel('com.pichillilorenzo/flutter_inappwebview_manager');
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('原生创建失败后初始化等待和释放不能永久挂起', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: '0', message: '无法创建网页组件');
    });
    final controller = CustomPlatformViewController();
    await expectLater(
        controller.initialize(), throwsA(isA<PlatformException>()));
    await expectLater(
        controller.ready.timeout(const Duration(milliseconds: 100)), completes);
    await expectLater(
        controller.dispose().timeout(const Duration(milliseconds: 100)),
        completes);
  });

  test('退出页面后才创建成功的组件必须释放且不再调用页面回调', () async {
    final creation = Completer<int>();
    final disposed = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'createInAppWebView') return creation.future;
      if (call.method == 'dispose') disposed.add(call.arguments['id'] as int);
      return null;
    });
    final controller = CustomPlatformViewController();
    var callbackCalled = false;
    final initialization = controller.initialize(
        onPlatformViewCreated: (_) => callbackCalled = true);
    final disposal = controller.dispose();
    creation.complete(123);
    await initialization;
    await disposal.timeout(const Duration(milliseconds: 100));
    expect(callbackCalled, isFalse);
    expect(disposed, [123]);
  });
}
