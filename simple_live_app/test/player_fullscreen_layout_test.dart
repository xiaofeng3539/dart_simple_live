import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/live_room_page.dart';

class _Room extends LiveRoomController {
  _Room() : super(pSite: Sites.allSites['huya']!, pRoomId: '1');
  @override
  // ignore: must_call_super
  void onInit() {}
  @override
  // ignore: must_call_super
  void onClose() {}
}

class _Surface extends StatefulWidget {
  const _Surface({super.key});
  @override
  State<_Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<_Surface> {
  int deactivations = 0;
  @override
  void deactivate() {
    deactivations++;
    super.deactivate();
  }
  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(child: ColoredBox(color: Colors.black));
}

class _Page extends LiveRoomPage {
  const _Page(this.surfaceKey);
  final GlobalKey<_SurfaceState> surfaceKey;
  @override
  Widget buildMediaPlayer() => _Surface(key: surfaceKey);
  @override
  List<Widget> buildAppbarActions(BuildContext context) => [];
  @override
  Widget buildUserProfile(BuildContext context) => const SizedBox(height: 48);
  @override
  Widget buildMessageArea() => const Expanded(child: SizedBox());
  @override
  Widget buildBottomActions(BuildContext context) => const SizedBox(height: 48);
}

void main() {
  for (final size in [const Size(480, 720), const Size(960, 640)]) {
    testWidgets('窗口 $size 连续全屏切换不迁移视频子树', (tester) async {
      Get.testMode = true;
      final room = _Room();
      Get.put<LiveRoomController>(room);
      final key = GlobalKey<_SurfaceState>();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        Get.reset();
      });
      await tester.pumpWidget(MaterialApp(home: _Page(key)));
      await tester.pump();
      final original = key.currentState!;
      for (var i = 0; i < 30; i++) {
        // 同时覆盖布局先更新和尺寸通知先到达的时序。
        if (i.isEven) {
          room.fullScreenState.value = true;
          await tester.pump();
        }
        tester.view.physicalSize = const Size(1920, 1080);
        await tester.pump();
        room.fullScreenState.value = true;
        await tester.pump();
        expect(key.currentState, same(original));
        expect(tester.getSize(find.byType(_Surface)), const Size(1920, 1080));
        expect(find.byType(AppBar), findsNothing);
        expect(find.text('关注'), findsNothing);
        room.fullScreenState.value = false;
        await tester.pump();
        tester.view.physicalSize = size;
        await tester.pump();
        expect(key.currentState, same(original));
        expect(find.byType(AppBar), findsOneWidget);
      }
      expect(original.deactivations, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
