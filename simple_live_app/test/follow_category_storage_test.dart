import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class _Site extends HuyaSite {
  String? category = ' 英雄联盟 ';
  int statusRequests = 0;
  int detailRequests = 0;
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    statusRequests++;
    return true;
  }
  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    detailRequests++;
    return LiveRoomDetail(roomId: roomId, title: '', cover: '', userName: '',
        userAvatar: '', online: 0, status: true, url: '', categoryName: category);
  }
}

class _Service extends FollowService {
  @override
  // ignore: must_call_super
  void onInit() {}
}

FollowUser _user() => FollowUser(id: 'huya_1', roomId: '1', siteId: 'huya',
    userName: '测试主播', face: '', addTime: DateTime(2026));

// 模拟旧版本七字段记录，验证新增字段仍能读取旧数据。
class _LegacyAdapter extends FollowUserAdapter {
  @override
  void write(BinaryWriter writer, FollowUser obj) {
    writer..writeByte(7)..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.roomId)..writeByte(2)..write(obj.siteId)
      ..writeByte(3)..write(obj.userName)..writeByte(4)..write(obj.face)
      ..writeByte(5)..write(obj.addTime)..writeByte(6)..write(obj.tag);
  }
}

void main() {
  late Directory directory;
  late DBService db;
  late Site original;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('simple-live-category-test-');
    Hive.init(directory.path);
    Hive.registerAdapter(FollowUserAdapter(), override: true);
    db = Get.put(DBService());
    db.followBox = await Hive.openBox<FollowUser>('FollowUser');
    original = Sites.allSites['huya']!;
  });
  tearDown(() async {
    Sites.allSites['huya'] = original;
    await Hive.close();
    Get.reset();
    await directory.delete(recursive: true);
  });

  test('旧七字段关注记录可读取，分类JSON和Hive持久化可往返', () async {
    await db.followBox.close();
    Hive.registerAdapter(_LegacyAdapter(), override: true);
    var box = await Hive.openBox<FollowUser>('Legacy');
    await box.put('user', _user());
    await box.close();
    Hive.registerAdapter(FollowUserAdapter(), override: true);
    box = await Hive.openBox<FollowUser>('Legacy');
    final legacy = box.get('user')!;
    expect(legacy.categoryName, isNull);
    expect(legacy.userName, '测试主播');
    legacy.categoryName = '英雄联盟';
    await box.put('user', legacy);
    await box.close();
    box = await Hive.openBox<FollowUser>('Legacy');
    expect(box.get('user')!.categoryName, '英雄联盟');
    expect(FollowUser.fromJson(box.get('user')!.toJson()).categoryName, '英雄联盟');
  });

  test('保存现有详情分类不增加请求，无分类响应保留缓存，取消关注不被重新加入', () async {
    final site = _Site();
    Sites.allSites['huya'] = Site(id: original.id, name: original.name,
        logo: original.logo, liveSite: site);
    final item = _user();
    await db.addFollow(item);
    final service = _Service();
    service.followList.add(item);
    await service.updateLiveStatus(item);
    expect(item.categoryName, '英雄联盟');
    expect(site.statusRequests, 1);
    expect(site.detailRequests, 1);
    await db.followBox.close();
    db.followBox = await Hive.openBox<FollowUser>('FollowUser');
    final restored = db.followBox.get(item.id)!;
    expect(restored.categoryName, '英雄联盟');
    site.category = null;
    await service.updateLiveStatus(restored);
    expect(restored.categoryName, '英雄联盟');
    await db.deleteFollow(item.id);
    site.category = '无畏契约';
    await service.updateLiveStatus(restored);
    expect(db.getFollowList(), isEmpty);
    expect(site.statusRequests, 3);
    expect(site.detailRequests, 3);
  });
}
