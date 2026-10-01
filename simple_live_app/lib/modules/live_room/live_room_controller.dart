import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';
import 'package:simple_live_app/modules/settings/danmu_settings_page.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/desktop_refresh_button.dart';
import 'package:simple_live_app/widgets/follow_user_item.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class LiveRoomController extends PlayerController with WidgetsBindingObserver {
  final Site pSite;
  final String pRoomId;
  late LiveDanmaku liveDanmaku;
  LiveRoomController({
    required this.pSite,
    required this.pRoomId,
  }) {
    rxSite = pSite.obs;
    rxRoomId = pRoomId.obs;
    liveDanmaku = site.liveSite.getDanmaku();
    // 抖音应该默认是竖屏的
    if (site.id == "douyin") {
      isVertical.value = true;
    }
  }

  late Rx<Site> rxSite;
  Site get site => rxSite.value;
  late Rx<String> rxRoomId;
  String get roomId => rxRoomId.value;

  Rx<LiveRoomDetail?> detail = Rx<LiveRoomDetail?>(null);
  var online = 0.obs;
  var followed = false.obs;
  var liveStatus = false.obs;
  RxList<LiveSuperChatMessage> superChats = RxList<LiveSuperChatMessage>();

  /// 滚动控制
  final ScrollController scrollController = ScrollController();
  bool _chatScrollScheduled = false;

  /// 聊天信息
  RxList<LiveMessage> messages = RxList<LiveMessage>();

  /// 清晰度数据
  RxList<LivePlayQuality> qualites = RxList<LivePlayQuality>();

  /// 当前清晰度
  var currentQuality = -1;
  var currentQualityInfo = "".obs;

  /// 线路数据
  RxList<String> playUrls = RxList<String>();

  Map<String, String>? playHeaders;

  /// 当前线路
  var currentLineIndex = -1;
  var currentLineInfo = "".obs;

  /// 退出倒计时
  var countdown = 60.obs;

  Timer? autoExitTimer;

  /// 设置的自动关闭时间（分钟）
  var autoExitMinutes = 60.obs;

  ///是否延迟自动关闭
  var delayAutoExit = false.obs;

  /// 是否启用自动关闭
  var autoExitEnable = false.obs;

  /// 是否禁用自动滚动聊天栏
  /// - 当用户向上滚动聊天栏时，不再自动滚动
  var disableAutoScroll = false.obs;

  /// 是否处于后台
  var isBackground = false;

  /// 直播间加载失败
  var loadError = false.obs;
  Object? error;
  StackTrace? errorStackTrace;

  // 开播时长状态变量
  var liveDuration = "00:00:00".obs;
  Timer? _liveDurationTimer;
  Timer? _volumeSliderTimer;
  bool _volumeSliderOpen = false;
  static const _volumeSliderTag = 'simple-live-volume-slider';
  int _roomRequest = 0;
  int _playRequest = 0;
  Future<void> _playerOperation = Future<void>.value();
  Timer? _bufferingTimer;
  Timer? _playbackFailureTimer;
  bool _recoveringPlayback = false;
  bool _roomClosed = false;
  bool _isCurrentRoomRequest(int request) =>
      !_roomClosed && request == _roomRequest;
  bool _isCurrentRequest(int request) =>
      !_roomClosed && request == _playRequest;

  @override
  void onInit() {
    WidgetsBinding.instance.addObserver(this);
    if (FollowService.instance.followList.isEmpty) {
      FollowService.instance.loadData();
    }
    initAutoExit();
    showDanmakuState.value = AppSettingsController.instance.danmuEnable.value;
    followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");
    loadData();

    scrollController.addListener(scrollListener);

    super.onInit();
  }

  void scrollListener() {
    if (scrollController.position.userScrollDirection ==
        ScrollDirection.forward) {
      disableAutoScroll.value = true;
    }
  }

  /// 初始化自动关闭倒计时
  void initAutoExit() {
    if (AppSettingsController.instance.autoExitEnable.value) {
      autoExitEnable.value = true;
      autoExitMinutes.value =
          AppSettingsController.instance.autoExitDuration.value;
      setAutoExit();
    } else {
      autoExitMinutes.value =
          AppSettingsController.instance.roomAutoExitDuration.value;
    }
  }

  void setAutoExit() {
    if (!autoExitEnable.value) {
      autoExitTimer?.cancel();
      return;
    }
    autoExitTimer?.cancel();
    countdown.value = autoExitMinutes.value * 60;
    autoExitTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      countdown.value -= 1;
      if (countdown.value <= 0) {
        timer = Timer(const Duration(seconds: 10), () async {
          await WakelockPlus.disable();
          exit(0);
        });
        autoExitTimer?.cancel();
        var delay = await Utils.showAlertDialog("定时关闭已到时,是否延迟关闭?",
            title: "延迟关闭", confirm: "延迟", cancel: "关闭", selectable: true);
        if (delay) {
          timer.cancel();
          delayAutoExit.value = true;
          showAutoExitSheet();
          setAutoExit();
        } else {
          delayAutoExit.value = false;
          await WakelockPlus.disable();
          exit(0);
        }
      }
    });
  }
  // 弹窗逻辑

  void refreshRoom() {
    //messages.clear();
    superChats.clear();
    liveDanmaku.stop();

    loadData();
  }

  /// 聊天栏始终滚动到底部
  void chatScrollToBottom() {
    if (scrollController.hasClients) {
      // 如果手动上拉过，就不自动滚动到底部
      if (disableAutoScroll.value) {
        return;
      }
      final position = scrollController.position;
      if (position.pixels != position.maxScrollExtent) {
        scrollController.jumpTo(position.maxScrollExtent);
      }
    }
  }

  /// 初始化弹幕接收事件
  void initDanmau() {
    liveDanmaku.onMessage = onWSMessage;
    liveDanmaku.onClose = onWSClose;
    liveDanmaku.onReady = onWSReady;
  }

  /// 接收到WebSocket信息
  void onWSMessage(LiveMessage msg) {
    if (msg.type == LiveMessageType.chat) {
      if (messages.length > 200 && !disableAutoScroll.value) {
        messages.removeAt(0);
      }

      // 关键词屏蔽检查
      for (var keyword in AppSettingsController.instance.shieldList) {
        Pattern? pattern;
        if (Utils.isRegexFormat(keyword)) {
          String removedSlash = Utils.removeRegexFormat(keyword);
          try {
            pattern = RegExp(removedSlash);
          } catch (e) {
            // should avoid this during add keyword
            Log.d("关键词：$keyword 正则格式错误");
          }
        } else {
          pattern = keyword;
        }
        if (pattern != null && msg.message.contains(pattern)) {
          Log.d("关键词：$keyword\n已屏蔽消息内容：${msg.message}");
          return;
        }
      }

      messages.add(msg);

      // 同一帧消息合并滚动，避免每条消息重复提交布局后的滚动操作。
      if (!_chatScrollScheduled && !disableAutoScroll.value) {
        _chatScrollScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _chatScrollScheduled = false;
          if (!_roomClosed) chatScrollToBottom();
        });
      }
      if (!liveStatus.value || isBackground) {
        return;
      }

      addDanmaku([
        DanmakuContentItem(
          msg.message,
          color: Color.fromARGB(
            255,
            msg.color.r,
            msg.color.g,
            msg.color.b,
          ),
        ),
      ]);
    } else if (msg.type == LiveMessageType.online) {
      online.value = msg.data;
    } else if (msg.type == LiveMessageType.superChat) {
      superChats.add(msg.data);
    }
  }

  /// 添加一条系统消息
  void addSysMsg(String msg) {
    messages.add(
      LiveMessage(
        type: LiveMessageType.chat,
        userName: "LiveSysMessage",
        message: msg,
        color: LiveMessageColor.white,
      ),
    );
  }

  /// 接收到WebSocket关闭信息
  void onWSClose(String msg) {
    addSysMsg(msg);
  }

  /// WebSocket准备就绪
  void onWSReady() {
    addSysMsg("弹幕服务器连接正常");
  }

  /// 加载直播间信息
  void loadData() async {
    if (_roomClosed) return;
    _bufferingTimer?.cancel();
    _bufferingTimer = null;
    _playbackFailureTimer?.cancel();
    final request = ++_roomRequest;
    final playRequest = ++_playRequest;
    playUrls.clear();
    currentLineIndex = -1;
    currentLineInfo.value = "";
    try {
      SmartDialog.showLoading(msg: "");
      loadError.value = false;
      error = null;
      errorStackTrace = null;
      update();
      addSysMsg("正在读取直播间信息");
      final roomSite = site;
      final roomIdToLoad = roomId;
      final roomDetail =
          await roomSite.liveSite.getRoomDetail(roomId: roomIdToLoad);
      if (!_isCurrentRoomRequest(request)) return;
      detail.value = roomDetail;

      if (site.id == Constant.kDouyin) {
        // 1.6.0之前收藏的WebRid
        // 1.6.0收藏的RoomID
        // 1.6.0之后改回WebRid
        if (detail.value!.roomId != roomId) {
          var oldId = roomId;
          rxRoomId.value = detail.value!.roomId;
          if (followed.value) {
            // 更新关注列表
            DBService.instance.deleteFollow("${site.id}_$oldId");
            DBService.instance.addFollow(
              FollowUser(
                id: "${site.id}_$roomId",
                roomId: roomId,
                siteId: site.id,
                userName: detail.value!.userName,
                face: detail.value!.userAvatar,
                addTime: DateTime.now(),
              ),
            );
          } else {
            followed.value =
                DBService.instance.getFollowExist("${site.id}_$roomId");
          }
        }
      }

      getSuperChatMessage(request);

      addHistory();
      // 确认房间关注状态
      followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");
      online.value = detail.value!.online;
      liveStatus.value = detail.value!.status || detail.value!.isRecord;
      if (liveStatus.value) {
        getPlayQualites(playRequest);
      } else {
        await _playerOperation;
        if (!_isCurrentRoomRequest(request)) return;
        await player.stop();
      }
      if (detail.value!.isRecord) {
        addSysMsg("当前主播未开播，正在轮播录像");
      }
      addSysMsg("开始连接弹幕服务器");
      initDanmau();
      liveDanmaku.start(detail.value?.danmakuData);
      startLiveDurationTimer(); // 启动开播时长定时器
    } catch (e, stackTrace) {
      if (!_isCurrentRoomRequest(request)) return;
      Log.logPrint(e);
      //SmartDialog.showToast(e.toString());
      loadError.value = true;
      error = e;
      errorStackTrace = stackTrace;
    } finally {
      if (_isCurrentRoomRequest(request)) {
        SmartDialog.dismiss(status: SmartStatus.loading);
      }
    }
  }

  /// 初始化播放器
  void getPlayQualites(int request) async {
    qualites.clear();
    currentQuality = -1;

    try {
      var playQualites =
          await site.liveSite.getPlayQualites(detail: detail.value!);
      if (!_isCurrentRequest(request)) return;

      if (playQualites.isEmpty) {
        SmartDialog.showToast("无法读取播放清晰度");
        return;
      }
      qualites.value = playQualites;
      var qualityLevel = await getQualityLevel();
      if (!_isCurrentRequest(request)) return;
      if (qualityLevel == 2) {
        //最高
        currentQuality = 0;
      } else if (qualityLevel == 0) {
        //最低
        currentQuality = playQualites.length - 1;
      } else {
        //中间值
        int middle = (playQualites.length / 2).floor();
        currentQuality = middle;
      }

      getPlayUrl(request: request);
    } catch (e) {
      if (!_isCurrentRequest(request)) return;
      Log.logPrint(e);
      SmartDialog.showToast("无法读取播放清晰度");
    }
  }

  Future<int> getQualityLevel() async {
    var qualityLevel = AppSettingsController.instance.qualityLevel.value;
    try {
      var connectivityResult = await (Connectivity().checkConnectivity());
      if (connectivityResult.first == ConnectivityResult.mobile) {
        qualityLevel =
            AppSettingsController.instance.qualityLevelCellular.value;
      }
    } catch (e) {
      Log.logPrint(e);
    }
    return qualityLevel;
  }

  void getPlayUrl({int? request}) async {
    final currentRequest = request ?? ++_playRequest;
    if (!_isCurrentRequest(currentRequest) ||
        currentQuality < 0 ||
        currentQuality >= qualites.length ||
        detail.value == null) {
      return;
    }
    final quality = qualites[currentQuality];
    final roomDetail = detail.value!;
    try {
      final playUrl =
          await site.liveSite.getPlayUrls(detail: roomDetail, quality: quality);
      if (!_isCurrentRequest(currentRequest)) return;
      if (playUrl.urls.isEmpty) {
        SmartDialog.showToast("无法读取播放地址");
        return;
      }
      playUrls.value = playUrl.urls;
      playHeaders = playUrl.headers;
      currentQualityInfo.value = quality.quality;
      currentLineIndex = 0;
      currentLineInfo.value = "线路1";
      mediaErrorRetryCount = 0;
      initPlaylist(currentRequest);
    } catch (e) {
      if (!_isCurrentRequest(currentRequest)) return;
      Log.logPrint(e);
      SmartDialog.showToast("无法读取播放地址");
    }
  }

  void changePlayLine(int index) {
    if (index < 0 || index >= playUrls.length) return;
    _bufferingTimer?.cancel();
    currentLineIndex = index;
    //重置错误次数
    mediaErrorRetryCount = 0;
    setPlayer();
  }

  void initPlaylist(int request) async {
    currentLineInfo.value = "线路${currentLineIndex + 1}";
    errorMsg.value = "";

    final mediaList = playUrls.map((url) {
      var finalUrl = url;
      if (AppSettingsController.instance.playerForceHttps.value) {
        finalUrl = finalUrl.replaceAll("http://", "https://");
      }
      return Media(finalUrl, httpHeaders: playHeaders);
    }).toList();
    final lineIndex = currentLineIndex;

    _playerOperation = _playerOperation.then((_) async {
      if (!_isCurrentRequest(request)) return;
      try {
        await initializePlayer();
        if (!_isCurrentRequest(request) || currentLineIndex != lineIndex) return;
        // 线路由房间控制器管理，避免播放器自动推进与错误恢复同时切换。
        await player.open(mediaList[lineIndex]);
      } catch (e) {
        if (!_isCurrentRequest(request)) return;
        Log.logPrint(e);
        errorMsg.value = "播放失败";
      }
    });
  }

  Future<void> setPlayer() async {
    if (currentLineIndex < 0 || currentLineIndex >= playUrls.length) return;
    _bufferingTimer?.cancel();
    _bufferingTimer = null;
    _playbackFailureTimer?.cancel();
    currentLineInfo.value = "线路${currentLineIndex + 1}";
    errorMsg.value = "";
    final request = _playRequest;
    final lineIndex = currentLineIndex;
    final mediaUrl = playUrls[lineIndex];
    final headers = playHeaders;
    _playerOperation = _playerOperation.then((_) async {
      if (!_isCurrentRequest(request) || currentLineIndex != lineIndex) return;
      try {
        var url = mediaUrl;
        if (AppSettingsController.instance.playerForceHttps.value) {
          url = url.replaceAll('http://', 'https://');
        }
        await player.open(Media(url, httpHeaders: headers));
      } catch (e) {
        if (!_isCurrentRequest(request)) return;
        Log.logPrint(e);
        errorMsg.value = "播放失败";
      }
    });
    await _playerOperation;
  }

  @override
  void mediaEnd() {
    _checkPlaybackFailure();
  }

  int mediaErrorRetryCount = 0;
  @override
  void mediaError(String error) {
    _checkPlaybackFailure(error: error);
  }

  void _checkPlaybackFailure({String? error}) {
    if (_roomClosed || isBackground || _recoveringPlayback ||
        playUrls.isEmpty || (_playbackFailureTimer?.isActive ?? false)) {
      return;
    }
    final request = _playRequest;
    final line = currentLineIndex;
    final position = player.state.position;
    // SDK 的错误流包含可恢复的解码和网络日志，不能每条日志都清空视频重连。
    _playbackFailureTimer = Timer(const Duration(seconds: 3), () {
      _playbackFailureTimer = null;
      if (!_isCurrentRequest(request) || currentLineIndex != line || isBackground) {
        return;
      }
      final state = player.state;
      if (state.position > position ||
          (state.playing && !state.buffering && !state.completed)) {
        return;
      }
      // 结束通知可能属于上一条流，只有当前流也结束时才恢复。
      if (error == null && !state.completed) return;
      _recoverPlayback(error: error);
    });
  }

  Future<void> _recoverPlayback({String? error}) async {
    final request = _playRequest;
    if (_recoveringPlayback || !_isCurrentRequest(request) || playUrls.isEmpty) return;
    _recoveringPlayback = true;
    _bufferingTimer?.cancel();
    try {
      if (site.id == Constant.kHuya && detail.value != null &&
          currentQuality >= 0 && currentQuality < qualites.length) {
        final line = currentLineIndex;
        final oldUri = Uri.tryParse(playUrls[line]);
        try {
          final fresh = await site.liveSite.getPlayUrls(
              detail: detail.value!, quality: qualites[currentQuality]);
          if (!_isCurrentRequest(request) || currentLineIndex != line) return;
          if (fresh.urls.isNotEmpty) {
            final sameLine = fresh.urls.indexWhere((url) {
              final uri = Uri.tryParse(url);
              return uri?.host == oldUri?.host && uri?.path == oldUri?.path;
            });
            playUrls.value = fresh.urls;
            playHeaders = fresh.headers;
            currentLineIndex = sameLine >= 0 ? sameLine : -1;
          }
        } catch (e) {
          Log.d('虎牙恢复鉴权失败：${e.runtimeType}');
        }
        if (!_isCurrentRequest(request) || isBackground) return;
      }
      // 优先切换备用线路，不在已失效的 CDN 上连续等待。
      if (currentLineIndex + 1 < playUrls.length) {
        currentLineIndex++;
        mediaErrorRetryCount = 0;
        await setPlayer();
      } else if (mediaErrorRetryCount < 2) {
        mediaErrorRetryCount++;
        await setPlayer();
      } else if (error == null) {
        liveStatus.value = false;
      } else {
        errorMsg.value = "播放失败";
        SmartDialog.showToast("播放失败:$error");
      }
    } finally {
      _recoveringPlayback = false;
    }
  }

  @override
  void mediaBuffering(bool buffering) {
    if (!buffering) {
      _bufferingTimer?.cancel();
      _bufferingTimer = null;
      return;
    }
    if (_bufferingTimer?.isActive ?? false) return;
    if (!buffering || _roomClosed || playUrls.isEmpty) return;
    final request = _playRequest;
    final line = currentLineIndex;
    final position = player.state.position;
    _bufferingTimer = Timer(const Duration(seconds: 15), () {
      _bufferingTimer = null;
      if (!_isCurrentRequest(request) || currentLineIndex != line ||
          isBackground || !liveStatus.value ||
          !player.state.buffering) {
        return;
      }
      if (player.state.position > position) {
        // 仍有播放进展时继续观察，不打断健康连接。
        mediaBuffering(true);
        return;
      }
      _recoverPlayback(error: "缓冲超时");
    });
  }

  /// 读取SC
  void getSuperChatMessage(int request) async {
    try {
      var sc =
          await site.liveSite.getSuperChatMessage(roomId: detail.value!.roomId);
      if (!_isCurrentRoomRequest(request)) return;
      superChats.addAll(sc);
    } catch (e) {
      if (!_isCurrentRoomRequest(request)) return;
      Log.logPrint(e);
      addSysMsg("SC读取失败");
    }
  }

  /// 移除掉已到期的SC
  void removeSuperChats() async {
    var now = DateTime.now().millisecondsSinceEpoch;
    superChats.value = superChats
        .where((x) => x.endTime.millisecondsSinceEpoch > now)
        .toList();
  }

  /// 添加历史记录
  void addHistory() {
    if (detail.value == null) {
      return;
    }
    var id = "${site.id}_$roomId";
    var history = DBService.instance.getHistory(id);
    if (history != null) {
      history.updateTime = DateTime.now();
    }
    history ??= History(
      id: id,
      roomId: roomId,
      siteId: site.id,
      userName: detail.value?.userName ?? "",
      face: detail.value?.userAvatar ?? "",
      updateTime: DateTime.now(),
    );

    DBService.instance.addOrUpdateHistory(history);
  }

  /// 关注用户
  void followUser() {
    if (detail.value == null) {
      return;
    }
    var id = "${site.id}_$roomId";
    DBService.instance.addFollow(
      FollowUser(
        id: id,
        roomId: roomId,
        siteId: site.id,
        userName: detail.value?.userName ?? "",
        face: detail.value?.userAvatar ?? "",
        addTime: DateTime.now(),
      ),
    );
    followed.value = true;
    EventBus.instance.emit(Constant.kUpdateFollow, id);
  }

  /// 取消关注用户
  void removeFollowUser() async {
    if (detail.value == null) {
      return;
    }
    if (!await Utils.showAlertDialog("确定要取消关注该用户吗？", title: "取消关注")) {
      return;
    }

    var id = "${site.id}_$roomId";
    DBService.instance.deleteFollow(id);
    followed.value = false;
    EventBus.instance.emit(Constant.kUpdateFollow, id);
  }

  void share() {
    if (detail.value == null) {
      return;
    }
    SharePlus.instance.share(ShareParams(uri: Uri.parse(detail.value!.url)));
  }

  void copyUrl() {
    if (detail.value == null) {
      return;
    }
    Utils.copyToClipboard(detail.value!.url);
    SmartDialog.showToast("已复制直播间链接");
  }

  /// 复制新生成的直播流
  void copyPlayUrl() async {
    // 未开播不复制
    if (!liveStatus.value) {
      return;
    }
    var playUrl = await site.liveSite
        .getPlayUrls(detail: detail.value!, quality: qualites[currentQuality]);
    if (playUrl.urls.isEmpty) {
      SmartDialog.showToast("无法读取播放地址");
      return;
    }
    Utils.copyToClipboard(playUrl.urls.first);
    SmartDialog.showToast("已复制播放直链");
  }

  /// 底部打开播放器设置
  void showDanmuSettingsSheet() {
    Utils.showBottomSheet(
      title: "弹幕设置",
      child: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          DanmuSettingsView(
            danmakuController: danmakuController,
            onTapDanmuShield: () {
              Get.back();
              showDanmuShield();
            },
          ),
        ],
      ),
    );
  }

  void showVolumeSlider(BuildContext targetContext) {
    _volumeSliderTimer?.cancel();
    _volumeSliderTimer = Timer(const Duration(milliseconds: 2500), () {
      SmartDialog.dismiss(status: SmartStatus.attach, tag: _volumeSliderTag);
    });
    if (_volumeSliderOpen) return;
    _volumeSliderOpen = true;
    SmartDialog.showAttach(
      targetContext: targetContext,
      alignment: Alignment.topCenter,
      maskColor: const Color(0x00000000),
      tag: _volumeSliderTag,
      usePenetrate: true,
      useAnimation: false,
      onDismiss: () {
        _volumeSliderOpen = false;
        _volumeSliderTimer?.cancel();
      },
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: colors.surfaceContainerHigh,
            border: Border.all(color: colors.outlineVariant),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Obx(
            () => SizedBox(
              width: 208,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.volume_up_outlined,
                          size: 18, color: colors.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text('音量', style: TextStyle(color: colors.onSurface)),
                      const Spacer(),
                      Text(
                        '${AppSettingsController.instance.playerVolume.value.round()}%',
                        style: TextStyle(
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      min: 0,
                      max: 100,
                      value: AppSettingsController.instance.playerVolume.value,
                      onChanged: (newValue) {
                        player.setVolume(newValue);
                        AppSettingsController.instance
                            .setPlayerVolume(newValue);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void showQualitySheet() {
    Utils.showBottomSheet(
      title: "切换清晰度",
      child: RadioGroup(
        groupValue: currentQuality,
        onChanged: (e) {
          Get.back();
          currentQuality = e ?? 0;
          getPlayUrl();
        },
        child: ListView.builder(
          itemCount: qualites.length,
          itemBuilder: (_, i) {
            var item = qualites[i];
            return RadioListTile(
              value: i,
              title: Text(item.quality),
            );
          },
        ),
      ),
    );
  }

  void showPlayUrlsSheet() {
    Utils.showBottomSheet(
      title: "切换线路",
      child: RadioGroup(
        groupValue: currentLineIndex,
        onChanged: (e) {
          Get.back();
          //currentLineIndex = i;
          //setPlayer();
          changePlayLine(e ?? 0);
        },
        child: ListView.builder(
          itemCount: playUrls.length,
          itemBuilder: (_, i) {
            return RadioListTile(
              value: i,
              title: Text("线路${i + 1}"),
              secondary: Text(
                playUrls[i].contains(".flv") ? "FLV" : "HLS",
              ),
            );
          },
        ),
      ),
    );
  }

  void showPlayerSettingsSheet() {
    Utils.showBottomSheet(
      title: "画面尺寸",
      child: Obx(
        () => RadioGroup(
          groupValue: AppSettingsController.instance.scaleMode.value,
          onChanged: (e) {
            AppSettingsController.instance.setScaleMode(e ?? 0);
            updateScaleMode();
          },
          child: ListView(
            padding: AppStyle.edgeInsetsV12,
            children: const [
              RadioListTile(
                value: 0,
                title: Text("适应"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 1,
                title: Text("拉伸"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 2,
                title: Text("铺满"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 3,
                title: Text("16:9"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 4,
                title: Text("4:3"),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void showDanmuShield() {
    TextEditingController keywordController = TextEditingController();

    void addKeyword() {
      if (keywordController.text.isEmpty) {
        SmartDialog.showToast("请输入关键词");
        return;
      }

      AppSettingsController.instance
          .addShieldList(keywordController.text.trim());
      keywordController.text = "";
    }

    Utils.showBottomSheet(
      title: "关键词屏蔽",
      child: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          TextField(
            controller: keywordController,
            decoration: InputDecoration(
              contentPadding: AppStyle.edgeInsetsH12,
              border: const OutlineInputBorder(),
              hintText: "请输入关键词",
              suffixIcon: TextButton.icon(
                onPressed: addKeyword,
                icon: const Icon(Icons.add),
                label: const Text("添加"),
              ),
            ),
            onSubmitted: (e) {
              addKeyword();
            },
          ),
          AppStyle.vGap12,
          Obx(
            () => Text(
              "已添加${AppSettingsController.instance.shieldList.length}个关键词（点击移除）",
              style: Get.textTheme.titleSmall,
            ),
          ),
          AppStyle.vGap12,
          Obx(
            () => Wrap(
              runSpacing: 12,
              spacing: 12,
              children: AppSettingsController.instance.shieldList
                  .map(
                    (item) => InkWell(
                      borderRadius: AppStyle.radius24,
                      onTap: () {
                        AppSettingsController.instance.removeShieldList(item);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: AppStyle.radius24,
                        ),
                        padding: AppStyle.edgeInsetsH12.copyWith(
                          top: 4,
                          bottom: 4,
                        ),
                        child: Text(
                          item,
                          style: Get.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  void showFollowUserSheet() {
    Utils.showBottomSheet(
      title: "关注列表",
      child: Obx(
        () => Stack(
          children: [
            RefreshIndicator(
              onRefresh: FollowService.instance.loadData,
              child: ListView.builder(
                itemCount: FollowService.instance.liveList.length,
                itemBuilder: (_, i) {
                  var item = FollowService.instance.liveList[i];
                  return Obx(
                    () => FollowUserItem(
                      item: item,
                      playing: rxSite.value.id == item.siteId &&
                          rxRoomId.value == item.roomId,
                      onTap: () {
                        Get.back();
                        resetRoom(
                          Sites.allSites[item.siteId]!,
                          item.roomId,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            if (Platform.isLinux || Platform.isWindows || Platform.isMacOS)
              Positioned(
                right: 12,
                bottom: 12,
                child: Obx(
                  () => DesktopRefreshButton(
                    refreshing: FollowService.instance.updating.value,
                    onPressed: FollowService.instance.loadData,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void showAutoExitSheet() {
    if (AppSettingsController.instance.autoExitEnable.value &&
        !delayAutoExit.value) {
      SmartDialog.showToast("已设置了全局定时关闭");
      return;
    }
    Utils.showBottomSheet(
      title: "定时关闭",
      child: ListView(
        children: [
          Obx(
            () => SwitchListTile(
              title: Text(
                "启用定时关闭",
                style: Get.textTheme.titleMedium,
              ),
              value: autoExitEnable.value,
              onChanged: (e) {
                autoExitEnable.value = e;

                setAutoExit();
                //controller.setAutoExitEnable(e);
              },
            ),
          ),
          Obx(
            () => ListTile(
              enabled: autoExitEnable.value,
              title: Text(
                "自动关闭时间：${autoExitMinutes.value ~/ 60}小时${autoExitMinutes.value % 60}分钟",
                style: Get.textTheme.titleMedium,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                var value = await showTimePicker(
                  context: Get.context!,
                  initialTime: TimeOfDay(
                    hour: autoExitMinutes.value ~/ 60,
                    minute: autoExitMinutes.value % 60,
                  ),
                  initialEntryMode: TimePickerEntryMode.inputOnly,
                  builder: (_, child) {
                    return MediaQuery(
                      data: Get.mediaQuery.copyWith(
                        alwaysUse24HourFormat: true,
                      ),
                      child: child!,
                    );
                  },
                );
                if (value == null || (value.hour == 0 && value.minute == 0)) {
                  return;
                }
                var duration =
                    Duration(hours: value.hour, minutes: value.minute);
                autoExitMinutes.value = duration.inMinutes;
                AppSettingsController.instance
                    .setRoomAutoExitDuration(autoExitMinutes.value);
                //setAutoExitDuration(duration.inMinutes);
                setAutoExit();
              },
            ),
          ),
        ],
      ),
    );
  }

  void openNaviteAPP() async {
    var naviteUrl = "";
    var webUrl = "";
    if (site.id == Constant.kBiliBili) {
      naviteUrl = "bilibili://live/${detail.value?.roomId}";
      webUrl = "https://live.bilibili.com/${detail.value?.roomId}";
    } else if (site.id == Constant.kDouyin) {
      var args = detail.value?.danmakuData as DouyinDanmakuArgs;
      naviteUrl = "snssdk1128://webcast_room?room_id=${args.roomId}";
      webUrl = "https://live.douyin.com/${args.webRid}";
    } else if (site.id == Constant.kHuya) {
      var args = detail.value?.danmakuData as HuyaDanmakuArgs;
      naviteUrl =
          "yykiwi://homepage/index.html?banneraction=https%3A%2F%2Fdiy-front.cdn.huya.com%2Fzt%2Ffrontpage%2Fcc%2Fupdate.html%3Fhyaction%3Dlive%26channelid%3D${args.subSid}%26subid%3D${args.subSid}%26liveuid%3D${args.subSid}%26screentype%3D1%26sourcetype%3D0%26fromapp%3Dhuya_wap%252Fclick%252Fopen_app_guide%26&fromapp=huya_wap/click/open_app_guide";
      webUrl = "https://www.huya.com/${detail.value?.roomId}";
    } else if (site.id == Constant.kDouyu) {
      naviteUrl =
          "douyulink://?type=90001&schemeUrl=douyuapp%3A%2F%2Froom%3FliveType%3D0%26rid%3D${detail.value?.roomId}";
      webUrl = "https://www.douyu.com/${detail.value?.roomId}";
    }
    try {
      await launchUrlString(naviteUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("无法打开APP，将使用浏览器打开");
      await launchUrlString(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  void resetRoom(Site site, String roomId) async {
    if (this.site == site && this.roomId == roomId) {
      return;
    }

    final request = ++_roomRequest;
    ++_playRequest;
    rxSite.value = site;
    rxRoomId.value = roomId;

    // 清除全部消息
    liveDanmaku.stop();
    messages.clear();
    superChats.clear();
    danmakuController?.clear();

    // 重新设置LiveDanmaku
    liveDanmaku = site.liveSite.getDanmaku();

    // 停止播放
    await _playerOperation;
    if (!_isCurrentRoomRequest(request)) return;
    await player.stop();
    if (!_isCurrentRoomRequest(request)) return;

    // 刷新信息
    loadData();
  }

  void copyErrorDetail() {
    Utils.copyToClipboard('''直播平台：${rxSite.value.name}
房间号：${rxRoomId.value}
错误信息：
${error?.toString()}
----------------
${errorStackTrace ?? ''}''');
    SmartDialog.showToast("已复制错误信息");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused) {
      Log.d("进入后台");
      //进入后台，关闭弹幕
      danmakuController?.clear();
      isBackground = true;
    } else
    //返回前台
    if (state == AppLifecycleState.resumed) {
      Log.d("返回前台");
      isBackground = false;
    }
  }

  // 用于启动开播时长计算和更新的函数
  void startLiveDurationTimer() {
    // 如果不是直播状态或者 showTime 为空，则不启动定时器
    if (!(detail.value?.status ?? false) || detail.value?.showTime == null) {
      liveDuration.value = "00:00:00"; // 未开播时显示 00:00:00
      _liveDurationTimer?.cancel();
      return;
    }

    try {
      int startTimeStamp = int.parse(detail.value!.showTime!);
      // 取消之前的定时器
      _liveDurationTimer?.cancel();
      // 创建新的定时器，每秒更新一次
      _liveDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        int currentTimeStamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        int durationInSeconds = currentTimeStamp - startTimeStamp;

        int hours = durationInSeconds ~/ 3600;
        int minutes = (durationInSeconds % 3600) ~/ 60;
        int seconds = durationInSeconds % 60;

        String formattedDuration =
            '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        liveDuration.value = formattedDuration;
      });
    } catch (e) {
      liveDuration.value = "--:--:--"; // 错误时显示 --:--:--
    }
  }

  @override
  void onClose() async {
    _roomClosed = true;
    _bufferingTimer?.cancel();
    _playbackFailureTimer?.cancel();
    ++_roomRequest;
    ++_playRequest;
    SmartDialog.dismiss(status: SmartStatus.loading);
    _volumeSliderTimer?.cancel();
    if (_volumeSliderOpen) {
      SmartDialog.dismiss(status: SmartStatus.attach, tag: _volumeSliderTag);
    }
    WidgetsBinding.instance.removeObserver(this);
    scrollController.removeListener(scrollListener);
    autoExitTimer?.cancel();

    liveDanmaku.stop();
    danmakuController = null;
    _liveDurationTimer?.cancel(); // 页面关闭时取消定时器
    await _playerOperation;
    super.onClose();
  }
}
