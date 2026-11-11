import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class _Settings extends AppSettingsController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

// Gate only the external network; lifecycle, database and list publishing are real.
class _Site extends HuyaSite {
  final requests = <Completer<bool>>[];
  @override
  Future<bool> getLiveStatus({required String roomId}) {
    final request = Completer<bool>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async =>
      LiveRoomDetail(
          roomId: roomId,
          title: '',
          cover: '',
          userName: '主播',
          userAvatar: '',
          online: 1,
          status: true,
          url: '');
}

Future<void> _until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('等待关注刷新超时');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late FollowService service;
  late Site original;
  late _Site site;

  void lifecycle(AppLifecycleState state) =>
      binding.handleAppLifecycleStateChanged(state);

  setUp(() async {
    lifecycle(AppLifecycleState.resumed);
    directory = await Directory.systemTemp.createTemp('follow-foreground-');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(FollowUserAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(FollowUserTagAdapter());
    }
    final db = Get.put(DBService());
    db.followBox = await Hive.openBox<FollowUser>('follow');
    db.tagBox = await Hive.openBox<FollowUserTag>('tags');
    await db.followBox.put(
        'huya_1',
        FollowUser(
            id: 'huya_1',
            roomId: '1',
            siteId: 'huya',
            userName: '主播',
            face: '',
            addTime: DateTime(2026)));
    final settings = Get.put<AppSettingsController>(_Settings());
    settings.autoUpdateFollowEnable.value = false;
    original = Sites.allSites['huya']!;
    site = _Site();
    Sites.allSites['huya'] = Site(
        id: 'huya', name: original.name, logo: original.logo, liveSite: site);
    service = Get.put(FollowService());
    await service.loadData(updateStatus: false);
  });

  tearDown(() async {
    service.onClose();
    for (final request in site.requests) {
      if (!request.isCompleted) request.complete(false);
    }
    await Future<void>.delayed(Duration.zero);
    Sites.allSites['huya'] = original;
    Get.reset();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  for (final away in [AppLifecycleState.inactive, AppLifecycleState.paused]) {
    test('从${away.name}回到前台自动更新开播状态，每次只刷新一轮', () async {
      lifecycle(away);
      expect(site.requests, isEmpty);
      lifecycle(AppLifecycleState.resumed);
      await _until(() => site.requests.length == 1);
      site.requests.single.complete(true);
      await _until(
          () => service.liveList.length == 1 && !service.updating.value);
      expect(service.liveList.single.roomId, '1');
      lifecycle(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(site.requests.length, 1);

      lifecycle(away);
      lifecycle(AppLifecycleState.resumed);
      await _until(() => site.requests.length == 2);
      site.requests.last.complete(false);
      await _until(
          () => service.notLiveList.length == 1 && !service.updating.value);
      expect(service.liveList, isEmpty);
    });
  }

  test('已有刷新进行中时切回前台不重启或重复请求', () async {
    await service.loadData();
    await _until(() => site.requests.length == 1);
    lifecycle(AppLifecycleState.inactive);
    lifecycle(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(site.requests.length, 1);
    site.requests.single.complete(false);
    await _until(() => !service.updating.value);
    expect(service.notLiveList.length, 1);
  });

  test('首次resumed不额外刷新，关闭服务后不再监听前台事件', () async {
    lifecycle(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(site.requests, isEmpty);
    service.onClose();
    lifecycle(AppLifecycleState.inactive);
    lifecycle(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(site.requests, isEmpty);
  });
}
