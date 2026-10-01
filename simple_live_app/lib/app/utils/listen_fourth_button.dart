import 'package:flutter/gestures.dart';

/// 鼠标侧键点击手势识别器
/// - https://github.com/flutter/flutter/issues/115641
/// - https://github.com/witnet/my-wit-wallet/pull/261
class FourthButtonTapGestureRecognizer extends BaseTapGestureRecognizer {
  GestureTapDownCallback? onTapDown;

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    // 只识别鼠标返回侧键，不能抢占视频双击、按钮或手机触摸。
    return event.kind == PointerDeviceKind.mouse &&
        event.buttons == kBackMouseButton &&
        super.isPointerAllowed(event);
  }

  @override
  void handleTapDown({required PointerDownEvent down}) {
    final TapDownDetails details = TapDownDetails(
      globalPosition: down.position,
      localPosition: down.localPosition,
      kind: getKindForPointer(down.pointer),
    );
    switch (down.buttons) {
      case 8:
        if (onTapDown != null) {
          invokeCallback<void>('onTapDown', () => onTapDown!(details));
        }
        break;
      default:
    }
  }

  @override
  void handleTapCancel(
      {required PointerDownEvent down,
      PointerCancelEvent? cancel,
      required String reason}) {}

  @override
  void handleTapUp(
      {required PointerDownEvent down, required PointerUpEvent up}) {}
}
