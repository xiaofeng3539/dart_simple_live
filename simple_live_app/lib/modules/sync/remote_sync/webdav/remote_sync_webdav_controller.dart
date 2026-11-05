import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/sync/remote_sync/webdav/webdav_client.dart';
import 'package:simple_live_app/modules/sync/remote_sync/webdav/webdav_backup_merge.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

class RemoteSyncWebDAVController extends BaseController {
  // ui
  var passwordVisible = true.obs;
  // ui-用户选择是否同步
  var isSyncFollows = true.obs;
  var isSyncHistories = true.obs;
  var isSyncBlockWord = true.obs;
  var isSyncBilibiliAccount = true.obs;

  final isSyncing = false.obs;

  late DAVClient davClient;
  var user = "--".obs;
  var lastRecoverTime = "--".obs;
  var lastUploadTime = "--".obs;

  final _userFollowJsonName = 'SimpleLive_follows.json';
  final _userHistoriesJsonName = 'SimpleLive_histories.json';
  final _userBlockedWordJsonName = 'SimpleLive_blocked_word.json';
  final _userBilibiliAccountJsonName = 'SimpleLive_bilibili_account.json';
  final _userSettingsJsonName = 'SimpleLive_Settings.json';
  final _userTagsJsonName = 'SimpleLive_Tags.json';

  @override
  void onInit() {
    doWebDAVInit();
    super.onInit();
  }

  // webDAV 逻辑
  // 初始化webDAV
  void doWebDAVInit() {
    var uri = LocalStorageService.instance
        .getValue(LocalStorageService.kWebDAVUri, "");
    if (uri.isEmpty) {
      notLogin.value = true;
    } else {
      user.value = LocalStorageService.instance
          .getValue(LocalStorageService.kWebDAVUser, "");
      var password = LocalStorageService.instance
          .getValue(LocalStorageService.kWebDAVPassword, "");
      davClient = DAVClient(uri, user.value, password);
      // 从未同步过默认为最新数据
      lastRecoverTime.value = Utils.parseTime(
        DateTime.fromMillisecondsSinceEpoch(
          LocalStorageService.instance.getValue(
            LocalStorageService.kWebDAVLastRecoverTime,
            DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      );
      lastUploadTime.value = Utils.parseTime(
        DateTime.fromMillisecondsSinceEpoch(
          LocalStorageService.instance.getValue(
            LocalStorageService.kWebDAVLastUploadTime,
            DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      );
      checkIsLogin();
    }
  }

  // 检查webDAV登录状态
  Future<void> checkIsLogin() async {
    try {
      // 返回登录结果
      bool value = await davClient.pingCompleter.future;
      notLogin.value = !value;
    } catch (e) {
      Log.e("$e", StackTrace.current);
      notLogin.value = true;
    }
  }

  // WebDAV登录
  void doWebDAVLogin(
      String webDAVUri, String webDAVUser, String webDAVPassword) async {
    // 确认登录
    davClient = DAVClient(webDAVUri, webDAVUser, webDAVPassword);
    await checkIsLogin();
    if (!notLogin.value) {
      // 保存到本地
      LocalStorageService.instance
          .setValue(LocalStorageService.kWebDAVUri, webDAVUri);
      LocalStorageService.instance
          .setValue(LocalStorageService.kWebDAVUser, webDAVUser);
      user.value = webDAVUser;
      LocalStorageService.instance
          .setValue(LocalStorageService.kWebDAVPassword, webDAVPassword);
      Get.back();
      SmartDialog.showToast("登录成功！");
    } else {
      SmartDialog.showToast("WebDAV账号密码验证失败，请重新输入！");
    }
  }

  // WebDAV登出
  @override
  Future<void> onLogout() async {
    if (isSyncing.value) return;
    var result = await Utils.showAlertDialog("确定要登出WebDAV账号？", title: "退出登录");
    if (result) {
      // 清除本地账号数据
      LocalStorageService.instance.setValue(LocalStorageService.kWebDAVUri, "");
      LocalStorageService.instance
          .setValue(LocalStorageService.kWebDAVUser, "");
      LocalStorageService.instance
          .setValue(LocalStorageService.kWebDAVPassword, "");
      notLogin.value = true;
    }
  }

  // Both platforms share this additive upload; the client retains cloud records.
  Future<void> doWebDAVUpload() async {
    if (isSyncing.value) return;
    isSyncing.value = true;
    SmartDialog.showLoading(msg: "正在上传并补充云端未关注的");
    try {
      final data = await _backupData();
      await davClient.backup(Uint8List.fromList(data));
      final uploadTime = DateTime.now();
      await LocalStorageService.instance.setValue(
        LocalStorageService.kWebDAVLastUploadTime,
        uploadTime.millisecondsSinceEpoch,
      );
      lastUploadTime.value = Utils.parseTime(uploadTime);
      SmartDialog.showToast("上传完成：已保留云端已有关注并补充新增关注");
    } catch (e, stack) {
      Log.e('上传合并失败: $e', stack);
      SmartDialog.showToast('上传失败：$e');
    } finally {
      SmartDialog.dismiss(status: SmartStatus.loading);
      isSyncing.value = false;
    }
  }

  // Build in memory: no shared temporary directory, stale files or plaintext copies.
  Future<List<int>> _backupData() async {
    final archive = Archive();
    void add(String name, dynamic data) {
      final bytes = utf8.encode(jsonEncode({'data': data}));
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    add(_userFollowJsonName,
        DBService.instance.getFollowList().map((e) => e.toJson()).toList());
    add(_userTagsJsonName,
        DBService.instance.getFollowTagList().map((e) => e.toJson()).toList());
    add(_userHistoriesJsonName,
        DBService.instance.getHistores().map((e) => e.toJson()).toList());
    add(_userBlockedWordJsonName,
        AppSettingsController.instance.shieldList.toList());
    add(_userBilibiliAccountJsonName,
        {'cookie': BiliBiliAccountService.instance.cookie});
    add(_userSettingsJsonName,
        LocalStorageService.instance.settingsBox.toMap());
    return ZipEncoder().encode(archive);
  }

  Future<void> _recoverFollows(Archive incoming) async {
    final db = DBService.instance;
    await db.runFollowTagMutation(() async {
      final journal = await Hive.openBox<dynamic>('webdav_restore_journal');
      // Finish the durable previous plan before taking a new destination snapshot.
      // This also works after process restart and when the cloud snapshot changes.
      await _applyFollowRestoreJournal(journal);
      final snapshot = Archive();
      void add(String name, dynamic value) {
        final bytes = utf8.encode(jsonEncode({'data': value}));
        snapshot.addFile(ArchiveFile(name, bytes.length, bytes));
      }

      add(_userFollowJsonName,
          db.getFollowList().map((e) => e.toJson()).toList());
      add(_userTagsJsonName,
          db.getFollowTagList().map((e) => e.toJson()).toList());
      final followArchive = Archive();
      for (final file in incoming) {
        if (file.name == _userFollowJsonName ||
            file.name == _userTagsJsonName) {
          followArchive.addFile(file);
        }
      }
      final merged = mergeWebDavBackups(snapshot, followArchive);
      List<dynamic> read(String name) =>
          jsonDecode(utf8.decode(merged.findFile(name)!.content))['data'];
      // Parse the entire merge before writes, so malformed input adds nothing.
      final users = read(_userFollowJsonName)
          .map((row) => FollowUser.fromJson(Map<String, dynamic>.from(row)))
          .toList();
      final tags = read(_userTagsJsonName)
          .map((row) => FollowUserTag.fromJson(Map<String, dynamic>.from(row)))
          .toList();
      final existingIds = db.followBox.values.map((e) => e.id).toSet();
      final additions =
          users.where((user) => !existingIds.contains(user.id)).toList();
      final addedIds = additions.map((user) => user.id).toSet();
      if (additions.isNotEmpty) {
        // Write-ahead intent must reach disk BEFORE adding any follow. Store only
        // newly owned IDs: replay must never regroup ordinary existing follows.
        await journal.put('pending', {
          'users': additions.map((user) => user.toJson()).toList(),
          'tags': tags
              .map((tag) => tag
                  .copyWith(
                      userId: tag.userId.where(addedIds.contains).toList())
                  .toJson())
              .toList(),
        });
        await journal.flush();
        await _applyFollowRestoreJournal(journal);
      }
    });
    EventBus.instance.emit(Constant.kUpdateFollow, 0);
  }

  Future<void> _applyFollowRestoreJournal(Box<dynamic> journal) async {
    final pending = journal.get('pending');
    if (pending == null) return;
    final db = DBService.instance;
    // Decode all entries before writes; corrupt intent is an error, not success.
    final users = (pending['users'] as List)
        .map((row) => FollowUser.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    final tags = (pending['tags'] as List)
        .map((row) => FollowUserTag.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    final expected = {for (final user in users) user.id: user};
    for (final user in users) {
      if (!db.followBox.containsKey(user.id)) {
        await db.followBox.put(user.id, user);
      }
    }
    // O(follows + tags + memberships). Snapshot tag keys by persisted identity,
    // including legacy integer keys, without changing existing tag ordering.
    final existingTags = {
      for (final key in db.tagBox.keys) db.tagBox.get(key)!.id: key,
    };
    final existingByName = {
      for (final key in db.tagBox.keys) db.tagBox.get(key)!.tag: key,
    };
    for (final tag in tags) {
      final additions = tag.userId.where((id) {
        final current = db.followBox.get(id);
        // A user may have deliberately changed groups since an interrupted
        // restore. Repair only the still-owned, unchanged group assignment.
        return expected.containsKey(id) && current?.tag == expected[id]!.tag;
      }).toList();
      if (additions.isEmpty) continue;
      final key = existingTags[tag.id] ?? existingByName[tag.tag];
      if (key != null) {
        final current = db.tagBox.get(key)!;
        final members = current.userId.toSet();
        final missing = additions.where(members.add).toList();
        if (missing.isNotEmpty) {
          await db.tagBox.put(
              key, current.copyWith(userId: [...current.userId, ...missing]));
        }
        if (current.tag != tag.tag) {
          // The existing group may have been renamed while restore was
          // interrupted. Remap only journal-owned users, AFTER membership is
          // durable: a failure here can replay without losing the repair.
          await db.tagBox.flush();
          for (final id in additions) {
            final user = db.followBox.get(id)!;
            await db.followBox.put(
                id,
                FollowUser.fromJson({
                  ...user.toJson(),
                  'tag': current.tag,
                }));
          }
        }
      } else {
        await db.tagBox.put(tag.id, tag.copyWith(userId: additions));
        existingTags[tag.id] = tag.id;
        existingByName[tag.tag] = tag.id;
      }
    }
    // Keep intent on any failure, including flush, so replay remains idempotent.
    await db.followBox.flush();
    await db.tagBox.flush();
    await journal.delete('pending');
    await journal.flush();
  }

  // webDAV恢复到本地
  Future<void> doWebDAVRecovery() async {
    if (isSyncing.value) return;
    isSyncing.value = true;
    SmartDialog.showLoading(msg: "正在下载并补充本机未关注的");
    try {
      final data = await davClient.recovery();
      final archive = decodeWebDavBackup(data);
      if (isSyncFollows.value &&
          !archive.any((file) => file.name == _userFollowJsonName)) {
        throw const FormatException('备份中缺少关注列表');
      }
      if (isSyncFollows.value) await _recoverFollows(archive);
      var skippedCount = 0;
      final failures = <String>[];
      for (ArchiveFile file in archive) {
        if (file.name == _userFollowJsonName ||
            file.name == _userTagsJsonName) {
          continue;
        }
        try {
          skippedCount += await _recovery(file);
        } catch (e) {
          failures.add('${file.name}: $e');
          Log.e('恢复文件${file.name}失败: $e', StackTrace.current);
        }
      }
      if (failures.isNotEmpty || skippedCount > 0) {
        SmartDialog.showToast('部分同步：${failures.join('；')}，$skippedCount 条数据跳过');
        return;
      }
      SmartDialog.showToast('下载完成：已保留本机已有关注并补充未关注的');
      DateTime recoverTime = DateTime.now();
      lastRecoverTime.value = Utils.parseTime(recoverTime);
      await LocalStorageService.instance.setValue(
          LocalStorageService.kWebDAVLastRecoverTime,
          recoverTime.millisecondsSinceEpoch);
    } catch (e) {
      // 下载或解压失败时不清空本地数据，提示真实错误信息
      Log.e('恢复到本地失败: $e', StackTrace.current);
      SmartDialog.showToast('下载失败：$e');
    } finally {
      SmartDialog.dismiss(status: SmartStatus.loading);
      isSyncing.value = false;
    }
  }

  // 恢复单个备份文件，返回无法识别已跳过的条目数量
  Future<int> _recovery(ArchiveFile file) async {
    // 记录该文件中无法识别已跳过的条目数量
    var skippedCount = 0;
    if (file.isFile && file.name.endsWith('.json')) {
      var jsonString = utf8.decode(file.content);
      var jsonData = json.decode(jsonString)['data'];
      if (file.name == _userHistoriesJsonName && isSyncHistories.value) {
        try {
          // 先把所有条目解析到内存，单条解析失败跳过并计数，不中断整批
          var histories = <History>[];
          for (var item in jsonData) {
            try {
              histories.add(History.fromJson(item));
            } catch (e) {
              skippedCount++;
              Log.e('解析历史记录条目失败，已跳过: $e', StackTrace.current);
            }
          }
          for (var history in histories) {
            if (!DBService.instance.historyBox.containsKey(history.id)) {
              await DBService.instance.addOrUpdateHistory(history);
            }
          }
          Log.i('已同步用户观看历史记录');
        } catch (e) {
          Log.e('同步用户观看历史记录失败: $e', StackTrace.current);
          rethrow;
        }
      } else if (file.name == _userBlockedWordJsonName &&
          isSyncBlockWord.value) {
        try {
          for (var keyword in jsonData) {
            try {
              AppSettingsController.instance.addShieldList(keyword.trim());
            } catch (e) {
              skippedCount++;
              Log.e('解析屏蔽词条目失败，已跳过: $e', StackTrace.current);
            }
          }
          Log.i('已同步用户屏蔽词');
        } catch (e) {
          Log.e('同步用户屏蔽词失败:$e', StackTrace.current);
          rethrow;
        }
      } else if (file.name == _userBilibiliAccountJsonName &&
          isSyncBilibiliAccount.value) {
        try {
          var cookie = jsonData['cookie'];
          if (BiliBiliAccountService.instance.cookie.isEmpty &&
              cookie is String &&
              cookie.isNotEmpty) {
            BiliBiliAccountService.instance.setCookie(cookie);
            BiliBiliAccountService.instance.loadUserInfo();
          }
          Log.i('已同步哔哩哔哩账号');
        } catch (e) {
          Log.e('同步哔哩哔哩账号失败：$e', StackTrace.current);
          rethrow;
        }
      } else if (file.name == _userSettingsJsonName) {
        try {
          var settings = Map<String, dynamic>.from(jsonData);
          for (var entry in settings.entries) {
            if (!LocalStorageService.instance.settingsBox
                .containsKey(entry.key)) {
              await LocalStorageService.instance.settingsBox
                  .put(entry.key, entry.value);
            }
          }
          Log.i('已同步用户设置');
        } catch (e) {
          Log.e("同步用户设置失败：$e", StackTrace.current);
          rethrow;
        }
      } else {
        return skippedCount;
      }
    } else {
      Log.i('不是正确的文件名');
    }
    return skippedCount;
  }

  // ui控制--密码可见控制
  void changePasswordVisible() {
    passwordVisible.value = !passwordVisible.value;
  }

  void changeIsSyncFollows() {
    isSyncFollows.value = !isSyncFollows.value;
  }

  void changeIsSyncHistories() {
    isSyncHistories.value = !isSyncHistories.value;
  }

  void changeIsSyncBlockWord() {
    isSyncBlockWord.value = !isSyncBlockWord.value;
  }

  void changeIsSyncBilibiliAccount() {
    isSyncBilibiliAccount.value = !isSyncBilibiliAccount.value;
  }
}
