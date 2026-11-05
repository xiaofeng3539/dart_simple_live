import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'danmaku/models/danmaku_content_item.dart';

/// Equal providers share Flutter's decoded image/animation stream and the
/// existing app disk cache. Decode to at most 96px high, not full-size stickers.
ImageProvider emoticonImageProvider(LiveEmoticon image) =>
    ResizeImage.resizeIfNeeded(
        null,
        96,
        ExtendedNetworkImageProvider(image.url,
            cache: true,
            cacheMaxAge: const Duration(days: 7),
            timeLimit: const Duration(seconds: 4),
            retries: 0,
            printError: false,
            headers: image.headers));

List<DanmakuSpan> emoticonDanmakuSpans(List<LiveMessagePart> parts) => [
      for (final part in parts)
        if (part.emoticon case final LiveEmoticon image)
          DanmakuSpan.image(part.text, emoticonImageProvider(image),
              aspectRatio: image.aspectRatio)
        else
          DanmakuSpan.text(part.text),
    ];

class LiveMessageContent extends StatelessWidget {
  final String userName;
  final List<LiveMessagePart> parts;
  final double fontSize;
  final Color color;
  final ImageProvider Function(LiveEmoticon) imageProvider;
  const LiveMessageContent(
      {super.key,
      required this.userName,
      required this.parts,
      required this.fontSize,
      required this.color,
      this.imageProvider = emoticonImageProvider});

  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(
        text: '$userName：',
        style: TextStyle(color: Colors.grey, fontSize: fontSize),
        children: [
          for (final part in parts)
            if (part.emoticon case final LiveEmoticon image)
              WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Semantics(
                    label: part.text,
                    image: true,
                    child: Image(
                        image: imageProvider(image),
                        height: fontSize * 1.3,
                        width: fontSize * 1.3 * image.aspectRatio,
                        fit: BoxFit.contain,
                        // Keep the original label while loading and after decode/network
                        // errors; failed pictures must not erase the chat body.
                        frameBuilder: (context, child, frame, sync) =>
                            frame == null ? _fallback(part.text) : child,
                        errorBuilder: (context, error, stack) =>
                            _fallback(part.text)),
                  ))
            else
              TextSpan(text: part.text, style: TextStyle(color: color)),
        ],
      ));

  Widget _fallback(String text) =>
      Text(text, style: TextStyle(color: color, fontSize: fontSize));
}
