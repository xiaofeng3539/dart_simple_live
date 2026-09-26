import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/search_room_url.dart';
import 'package:simple_live_app/routes/app_navigation.dart';

class AppSearchController extends GetxController {
  final selectedSite = Rxn<Site>();
  final roomId = RxnString();
  void Function(String roomId)? onRoomDetected;
  String? _lastPromptedRoom;
  InAppWebViewController? webViewController;

  void selectSite(Site site) {
    roomId.value = null;
    _lastPromptedRoom = null;
    selectedSite.value = site;
  }

  void updateUrl(Uri? uri) {
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
    await webViewController?.reload();
  }

  Future<bool> openPopup(CreateWindowAction action) async {
    final url = action.request.url;
    if (url == null || webViewController == null) return false;
    updateUrl(url);
    await webViewController!.loadUrl(urlRequest: action.request);
    return false;
  }

  void openRoom({String? detectedRoomId}) {
    final site = selectedSite.value;
    final id = detectedRoomId ?? roomId.value;
    if (site == null || id == null) return;
    AppNavigator.toLiveRoomDetail(site: site, roomId: id);
  }
}
