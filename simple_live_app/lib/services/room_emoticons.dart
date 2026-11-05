import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// Room-scoped: an old network response can never overwrite a new room's map.
class RoomEmoticons extends ChangeNotifier {
  final EmoticonCatalog _catalog;
  final Future<List<LiveEmoticon>> Function(CancelToken) _fetch;
  final DateTime Function() _clock;
  int _attempts = 0;
  DateTime? _retryAt;
  CancelToken? _cancel;
  Future<void>? _pending;
  bool _disposed = false;
  bool _loaded = false;
  bool get loading => _pending != null;
  RoomEmoticons(
      {required String platform,
      required String roomId,
      dynamic args,
      Future<List<LiveEmoticon>> Function()? fetch,
      DateTime Function()? clock})
      : _catalog = EmoticonCatalog(emoticonSeeds(platform)),
        _clock = clock ?? DateTime.now,
        _fetch = ((cancel) => fetch != null
            ? fetch()
            : PlatformEmoticons()
                .load(platform, roomId, args: args, cancel: cancel));

  Future<void> load() {
    if (_disposed || _loaded) return Future.value();
    return _pending ??= Future<void>.microtask(_load);
  }

  /// Automatic retries are driven by unknown incoming tokens, not a timer;
  /// at most three requests per room, separated by 2s then 4s backoff.
  Future<void>? retryIfDue() {
    if (_disposed || _loaded) return null;
    if (_pending != null) return _pending;
    if (_attempts >= 3 || (_retryAt != null && _clock().isBefore(_retryAt!)))
      return null;
    return load();
  }

  Future<void> _load() async {
    _attempts++;
    final cancel = CancelToken();
    _cancel = cancel;
    try {
      final entries = await _fetch(cancel).timeout(const Duration(seconds: 5));
      if (_disposed) return;
      _catalog.addAll(entries);
      _loaded = true;
      notifyListeners();
    } catch (_) {
      _retryAt = _clock().add(Duration(seconds: 1 << _attempts.clamp(1, 4)));
      cancel.cancel('emoticon catalog unavailable');
      // Missing credentials, offline or a changed schema must never block
      // playback/chat. Keep seed/native images and allow a later retry.
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
      _pending = null;
    }
  }

  List<LiveMessagePart> resolve(LiveMessage message) {
    if (message.emoticonKey != null) {
      final match = _catalog.split(message.emoticonKey!).firstOrNull?.emoticon;
      if (match != null)
        return [
          LiveMessagePart.image(LiveEmoticon(
              text: message.message.isEmpty ? match.text : message.message,
              url: match.url,
              width: match.width,
              height: match.height,
              headers: match.headers))
        ];
    }
    return _catalog.enrich(message.parts);
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel('room closed');
    super.dispose();
  }
}
