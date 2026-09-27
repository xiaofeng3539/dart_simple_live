import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/search_controller.dart';
import 'package:simple_live_app/modules/search/search_room_url.dart';

class SearchPage extends GetView<AppSearchController> {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Obx(
          () => IconButton(
            tooltip: controller.selectedSite.value == null ? '返回' : '选择平台',
            onPressed: controller.selectedSite.value == null
                ? Get.back
                : controller.reset,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        title: Obx(
          () => Text(controller.selectedSite.value?.name ?? '搜索直播'),
        ),
        actions: [
          Obx(() {
            if (controller.selectedSite.value == null) {
              return const SizedBox.shrink();
            }
            return Row(
              children: [
                IconButton(
                  tooltip: '网页后退',
                  onPressed: controller.goBackInWebView,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: '刷新网页',
                  onPressed: controller.reloadWebView,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            );
          }),
        ],
      ),
      body: Obx(() {
        final site = controller.selectedSite.value;
        if (site == null) return _platformPicker(context);
        return Offstage(
          offstage: !controller.webViewVisible.value,
          child: InAppWebView(
            key: ValueKey(site.id),
            initialUrlRequest: URLRequest(
              url: WebUri(SearchRoomUrl.homeUriFor(site.id).toString()),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptCanOpenWindowsAutomatically: true,
              supportMultipleWindows: true,
            ),
            initialUserScripts: site.id == Constant.kDouyin
                ? UnmodifiableListView([
                    UserScript(
                      source: '''
                      document.addEventListener('click', function(event) {
                        var target = event.target;
                        if (!(target instanceof Element)) return;
                        var link = target.closest('a[href]');
                        if (link) {
                          window.flutter_inappwebview.callHandler(
                            'simpleLiveDouyinRoom', link.href);
                        }
                      }, true);
                    ''',
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      forMainFrameOnly: true,
                    ),
                  ])
                : null,
            onWebViewCreated: (webViewController) {
              controller.webViewController = webViewController;
              controller.onRoomDetected = _showRoomPrompt;
              if (site.id == Constant.kDouyin) {
                webViewController.addJavaScriptHandler(
                  handlerName: 'simpleLiveDouyinRoom',
                  callback: (args) {
                    if (controller.selectedSite.value?.id == site.id &&
                        args.isNotEmpty &&
                        args.first is String) {
                      final uri = Uri.tryParse(args.first as String);
                      if (uri != null &&
                          SearchRoomUrl.roomIdFor(site.id, uri) != null) {
                        controller.updateUrl(uri);
                      }
                    }
                  },
                );
              }
            },
            onLoadStart: (_, uri) => controller.updateUrl(uri),
            onLoadStop: (_, uri) => controller.updateUrl(uri),
            onUpdateVisitedHistory: (_, uri, __) => controller.updateUrl(uri),
            onCreateWindow: (_, action) => controller.openPopup(action),
          ),
        );
      }),
      bottomNavigationBar: Obx(() {
        if (controller.selectedSite.value == null ||
            !controller.webViewVisible.value ||
            controller.roomId.value == null) {
          return const SizedBox.shrink();
        }
        return SafeArea(
          child: Padding(
            padding: AppStyle.edgeInsetsA12,
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: controller.openRoom,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('在 Simple Live 中打开'),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  void _showRoomPrompt(String roomId) async {
    await Future<void>.delayed(Duration.zero);
    final site = controller.selectedSite.value;
    if (controller.isClosed || site == null) return;
    final open = await Get.dialog<bool>(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('已进入${site.name}直播间',
                    style: Get.theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('要在 Simple Live 中观看吗？',
                    style: Get.theme.textTheme.bodyMedium),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Get.back(result: false),
                      child: const Text('继续浏览'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Get.back(result: true),
                      child: const Text('打开播放器'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (open == true &&
        !controller.isClosed &&
        controller.selectedSite.value == site) {
      controller.openRoom(detectedRoomId: roomId);
    }
  }

  Widget _platformPicker(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: AppStyle.edgeInsetsA12,
          children: [
            Padding(
              padding: AppStyle.edgeInsetsA12,
              child: Text(
                '选择平台，在网页中搜索并进入直播间',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...Sites.supportSites.map(
              (site) => Card(
                child: ListTile(
                  leading: Image.asset(site.logo, width: 32, height: 32),
                  title: Text(site.name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => controller.selectSite(site),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
