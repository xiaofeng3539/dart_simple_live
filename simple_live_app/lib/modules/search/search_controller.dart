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
    webViewVisible.value = true;
    startLoading();
    roomId.value = null;
    _lastPromptedRoom = null;
    selectedSite.value = site;
  }

  void updateUrl(Uri? uri) {
    if (!webViewVisible.value) return;
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
    if (await webViewController?.canGoBack() ?? false) {
      await webViewController?.goBack();
    }
  }

  Future<void> reloadWebView() async {
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
    _loadTimer?.cancel();
    webViewLoading.value = false;
  }

  void failLoading(String message) {
    finishLoading();
    webViewError.value = message;
  }

  @override
  void onClose() {
    _loadTimer?.cancel();
    _disposeWebViewEnvironment();
    super.onClose();
  }

  Future<bool> openPopup(CreateWindowAction action) async {
    final url = action.request.url;
    if (url == null || webViewController == null) return false;
    updateUrl(url);
    await webViewController!.loadUrl(urlRequest: action.request);
    return false;
  }

  Future<void> openRoom({String? detectedRoomId}) async {
    final site = selectedSite.value;
    final id = detectedRoomId ?? roomId.value;
    if (site == null || id == null) return;
    if (site.id == Constant.kDouyin) {
      final webView = webViewController;
      await webView?.pause();
      webViewVisible.value = false;
      await WidgetsBinding.instance.endOfFrame;
      try {
        await AppNavigator.toLiveRoomDetail(site: site, roomId: id);
      } finally {
        if (!isClosed) {
          webViewVisible.value = true;
          await WidgetsBinding.instance.endOfFrame;
          await webView?.resume();
        }
      }
      return;
    }
    AppNavigator.toLiveRoomDetail(site: site, roomId: id);
  }
}
