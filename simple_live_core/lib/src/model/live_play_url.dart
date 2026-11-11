import 'dart:convert';
import '../common/native_quality.dart';

class LivePlayUrl {
  /// 播放地址
  final List<String> urls;

  /// 请求头
  final Map<String, String>? headers;
  final List<NativeHlsVariant> nativeVariants;
  final NativeHlsVariant? selectedNativeVariant;

  LivePlayUrl({
    required this.urls,
    this.headers,
    this.nativeVariants = const [],
    this.selectedNativeVariant,
  });

  @override
  String toString() {
    return json.encode({"urls": urls, "headers": headers.toString()});
  }
}
