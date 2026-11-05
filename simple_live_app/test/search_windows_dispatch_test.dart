import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// Exercise the real Windows plugin dispatcher, not a fake WebView controller.
// ignore: depend_on_referenced_packages
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/search_controller.dart';
import 'package:simple_live_app/modules/search/search_page.dart';

class _SearchController extends AppSearchController {
  @override
  Future<WebViewEnvironment?> get webViewEnvironment async => null;
}

Future<dynamic> nativeCall(int id, String method, dynamic args) async {
  const codec = StandardMethodCodec();
  final result = Completer<dynamic>();
  // ignore: deprecated_member_use
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
    'com.pichillilorenzo/flutter_inappwebview_$id',
    codec.encodeMethodCall(MethodCall(method, args)),
    (bytes) {
      try { result.complete(bytes == null ? null : codec.decodeEnvelope(bytes)); }
      catch (e, st) { result.completeError(e, st); }
    },
  );
  return result.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const manager = MethodChannel('com.pichillilorenzo/flutter_inappwebview_manager');
  final channels = <MethodChannel>[];
  var nextId = 800;
  late int id;
  setUp(() {
    WindowsInAppWebViewPlatform.registerWith();
    Get.testMode = true;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(manager, (call) async {
      if (call.method != 'createInAppWebView') return null;
      id = nextId++;
      for (final name in [
        'com.pichillilorenzo/custom_platform_view_$id',
        'com.pichillilorenzo/custom_platform_view_${id}_events',
        'com.pichillilorenzo/flutter_inappwebview_$id',
      ]) {
        final channel = MethodChannel(name);
        channels.add(channel);
        messenger.setMockMethodCallHandler(channel, (_) async => null);
      }
      return id;
    });
  });
  tearDown(() async {
    Get.reset();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(manager, null);
    for (final channel in channels) { messenger.setMockMethodCallHandler(channel, null); }
    channels.clear();
  });
  for (final site in Sites.allSites.values) {
    testWidgets('${site.name}：真实Windows回调包装不同也必须允许网页导航', (tester) async {
      final search = _SearchController();
      Get.put<AppSearchController>(search);
      search.selectSite(site);
      await tester.pumpWidget(const GetMaterialApp(home: SearchPage()));
      await tester.pump();
      await tester.pump();
      expect(search.webViewController, isNotNull);
      final action = NavigationAction(
        request: URLRequest(url: WebUri(search.webViewUrl.toString())),
        isForMainFrame: true,
      );
      final policy = await nativeCall(id, 'shouldOverrideUrlLoading', action.toMap());
      expect(policy, NavigationActionPolicy.ALLOW.toNativeValue(),
        reason: '插件onWebViewCreated和事件回调用不同Dart包装，不能将正常导航CANCEL');
      await nativeCall(id, 'onLoadStop', {'url': search.webViewUrl.toString()});
      await tester.pump();
      expect(search.webViewError.value, isNull);
      expect(search.webViewLoading.value, isFalse);
      // A real platform controller match must not bypass the revision guard.
      // This is still the old native channel before the next Flutter frame.
      search.selectSite(site);
      final latePolicy = await nativeCall(id, 'shouldOverrideUrlLoading', action.toMap());
      expect(latePolicy, NavigationActionPolicy.CANCEL.toNativeValue());
      search.onClose();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
}

