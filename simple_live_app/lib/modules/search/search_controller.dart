import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/search_room_url.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/routes/route_path.dart';

class AppSearchController extends GetxController {
  final selectedSite = Rxn<Site>();
  final roomId = RxnString();
  final webViewVisible = true.obs;
  final webViewLoading = false.obs;
  final webViewError = RxnString();
  void Function(String roomId)? onRoomDetected;
  String? _lastPromptedRoom;
  InAppWebViewController? webViewController;
  Future<WebViewEnvironment?>? _webViewEnvironment;
  Timer? _loadTimer;

  Future<WebViewEnvironment?> get webViewEnvironment =>
      _webViewEnvironment ??= _createWebViewEnvironment();

  Future<WebViewEnvironment?> _createWebViewEnvironment() async {
    if (!Platform.isWindows) return null;
    final supportDir = await getApplicationSupportDirectory();
    final profileDir = Directory(p.join(supportDir.path, 'search_webview'));
    await profileDir.create(recursive: true);
    return WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(userDataFolder: profileDir.path),
    );
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
    startLoading();
    await webViewController?.reload();
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
        await Get.toNamed(RoutePath.kLiveRoomDetail,
            arguments: site, parameters: {'roomId': id});
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
