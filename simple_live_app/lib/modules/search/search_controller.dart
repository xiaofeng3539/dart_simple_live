import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/search_room_url.dart';
import 'package:simple_live_app/routes/app_navigation.dart';

class AppSearchController extends GetxController {
  final selectedSite = Rxn<Site>();
  final roomId = RxnString();
  final webViewVisible = true.obs;
  final webViewLoading = false.obs;
  final webViewError = RxnString();
  final webViewRevision = 0.obs;
  void Function(String roomId)? onRoomDetected;
  String? _lastPromptedRoom;
  InAppWebViewController? webViewController;
  Future<WebViewEnvironment?>? _webViewEnvironment;
  Timer? _loadTimer;
  bool _closing = false;
  bool _openingRoom = false;

  bool _isCurrent(InAppWebViewController? view, int revision) =>
      !_closing && !isClosed && webViewRevision.value == revision &&
      identical(webViewController, view);

  Future<WebViewEnvironment?> get webViewEnvironment =>
      _webViewEnvironment ??= _createWebViewEnvironment();

  Future<WebViewEnvironment?> _createWebViewEnvironment() async {
    if (!Platform.isWindows) return null;
    final revision = webViewRevision.value;
    try {
      final supportDir = await getApplicationSupportDirectory();
      final profileDir = Directory(p.join(supportDir.path, 'search_webview'));
      await profileDir.create(recursive: true);
      final creation = WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(userDataFolder: profileDir.path),
      );
      try {
        return await creation.timeout(const Duration(seconds: 20));
      } on TimeoutException {
        // 超时不能取消原生创建；迟到的环境创建成功后仍需释放。
        unawaited(creation
            .then((environment) => environment.dispose())
            .catchError((Object error, StackTrace stackTrace) {
          Log.e('释放超时网页环境失败：$error', stackTrace);
        }));
        rethrow;
      }
    } catch (error, stackTrace) {
      Log.e('搜索页 WebView2 环境启动失败：$error', stackTrace);
      if (!isClosed && webViewRevision.value == revision) {
        final code =
            error is PlatformException ? int.tryParse(error.code) : null;
        final detail = code == null
            ? ''
            : '（错误码 0x${code.toUnsigned(32).toRadixString(16).padLeft(8, '0')}）';
        failLoading('网页组件启动失败，请点击右上角刷新重试$detail');
      }
      rethrow;
    }
  }

  void selectSite(Site site) {
    if (_closing || isClosed) return;
    webViewRevision.value++;
    webViewVisible.value = true;
    startLoading();
    roomId.value = null;
    _lastPromptedRoom = null;
    selectedSite.value = site;
  }

  void updateUrl(Uri? uri) {
    if (_closing || isClosed || !webViewVisible.value) return;
    final site = selectedSite.value;
    final detectedRoomId = site == null || uri == null
        ? null
        : SearchRoomUrl.roomIdFor(site.id, uri);
    roomId.value = detectedRoomId;
    if (site != null && detectedRoomId != null) {
      final roomKey = '${site.id}:$detectedRoomId';
      if (_lastPromptedRoom != roomKey) {
        _lastPromptedRoom = roomKey;
        onRoomDetected?.call(detectedRoomId);
      }
    }
  }

  void reset() {
    webViewRevision.value++;
    webViewController?.removeJavaScriptHandler(handlerName: 'simpleLiveDouyinRoom');
    onRoomDetected = null;
    _loadTimer?.cancel();
    webViewLoading.value = false;
    webViewError.value = null;
    webViewVisible.value = true;
    roomId.value = null;
    _lastPromptedRoom = null;
    selectedSite.value = null;
    webViewController = null;
  }

  Future<void> goBackInWebView() async {
    final view = webViewController;
    final revision = webViewRevision.value;
    if (!_isCurrent(view, revision) || view == null) return;
    if (await view.canGoBack() && _isCurrent(view, revision)) {
      await view.goBack();
    }
  }

  Future<void> reloadWebView() async {
    if (_closing || isClosed) return;
    final recreate = Platform.isWindows &&
        (webViewController == null || webViewError.value != null);
    if (recreate) {
      webViewController = null;
      _disposeWebViewEnvironment();
      webViewRevision.value++;
    }
    startLoading();
    if (!recreate) await webViewController?.reload();
  }

  void _disposeWebViewEnvironment() {
    final pending = _webViewEnvironment;
    _webViewEnvironment = null;
    if (pending == null) return;
    unawaited(pending.then((environment) async {
      await environment?.dispose();
    }).catchError((Object error, StackTrace stackTrace) {
      Log.e('释放搜索网页环境失败：$error', stackTrace);
    }));
  }

  void startLoading() {
    if (_closing || isClosed) return;
    webViewLoading.value = true;
    webViewError.value = null;
    _loadTimer?.cancel();
    _loadTimer = Timer(const Duration(seconds: 20), () {
      if (webViewLoading.value) {
        webViewLoading.value = false;
        webViewError.value = '网页加载超时，请点击右上角刷新重试';
      }
    });
  }

  void finishLoading() {
    if (_closing || isClosed) return;
    _loadTimer?.cancel();
    webViewLoading.value = false;
  }

  void failLoading(String message) {
    if (_closing || isClosed) return;
    finishLoading();
    webViewError.value = message;
  }

  @override
  void onClose() {
    if (_closing) return;
    _closing = true;
    webViewRevision.value++;
    webViewController?.removeJavaScriptHandler(handlerName: 'simpleLiveDouyinRoom');
    webViewController = null;
    onRoomDetected = null;
    _loadTimer?.cancel();
    _disposeWebViewEnvironment();
    super.onClose();
  }

  Future<bool> openPopup(CreateWindowAction action) async {
    final url = action.request.url;
    if (_closing || isClosed || url == null || webViewController == null) return false;
    updateUrl(url);
    // Windows 插件在返回 false 后执行默认导航，不能在两端重复 loadUrl。
    if (!Platform.isWindows) {
      await webViewController!.loadUrl(urlRequest: action.request);
    }
    return false;
  }

  Future<void> openRoom({String? detectedRoomId}) async {
    if (_closing || isClosed || _openingRoom) return;
    final site = selectedSite.value;
    final id = detectedRoomId ?? roomId.value;
    if (site == null || id == null) return;
    if (site.id == Constant.kDouyin) {
      final webView = webViewController;
      final revision = webViewRevision.value;
      _openingRoom = true;
      try {
        await webView?.pause();
        if (!_isCurrent(webView, revision)) return;
        webViewVisible.value = false;
        await WidgetsBinding.instance.endOfFrame;
        if (!_isCurrent(webView, revision)) return;
        await AppNavigator.toLiveRoomDetail(site: site, roomId: id);
      } finally {
        if (_isCurrent(webView, revision)) {
          webViewVisible.value = true;
          await WidgetsBinding.instance.endOfFrame;
          if (_isCurrent(webView, revision)) await webView?.resume();
        }
        _openingRoom = false;
      }
      return;
    }
    AppNavigator.toLiveRoomDetail(site: site, roomId: id);
  }
}
