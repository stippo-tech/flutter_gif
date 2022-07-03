///
/// * author: Pierluigi Zagaria
/// * email: pierluigizagaria@gmail.com
///
/// A package provides an easy way to manage Gifs with animation controllers
///

library gif;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

final HttpClient _sharedHttpClient = HttpClient()..autoUncompress = false;

HttpClient get _httpClient {
  HttpClient client = _sharedHttpClient;
  assert(() {
    if (debugNetworkImageHttpClientProvider != null) {
      client = debugNetworkImageHttpClientProvider!();
    }
    return true;
  }());
  return client;
}

///
/// A widget that renders a Gif controllable with [AnimationController].
///
@immutable
class Gif extends StatefulWidget {
  /// Rendered gifs cache.
  static GifCache cache = GifCache();

  /// [ImageProvider] of this gif. Like [NetworkImage], [AssetImage], [MemoryImage]
  final ImageProvider image;

  /// This playback controller.
  final AnimationController? controller;

  /// Frames per second at which this runs.
  final int? fps;

  /// Start the gif as soon as possible.
  final bool autostart;

  /// Rendered when gif frames fetch is still not completed.
  final Widget Function(BuildContext context)? placeholder;

  /// Called when gif frames fetch is completed.
  final VoidCallback? onFetchCompleted;

  final double? width;
  final double? height;
  final Color? color;
  final BlendMode? colorBlendMode;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final ImageRepeat repeat;
  final Rect? centerSlice;
  final bool matchTextDirection;
  final String? semanticLabel;
  final bool excludeFromSemantics;

  /// Creates a widget that displays a controllable gif.
  ///
  /// [fps] frames per second at which this should be rendered.
  /// If this is set, playback is paused and [controller.duration] is replaced.
  ///
  /// [autostart] start this gif as soon as possible. Defaults to true.
  ///
  /// [placeholder] this widget is rendered during the gif frames fetch.
  ///
  /// [onFetchCompleted] is called when the frames fetch finishes and the gif can be
  /// rendered.
  Gif({
    Key? key,
    required this.image,
    this.controller,
    this.fps,
    this.autostart = true,
    this.placeholder,
    this.onFetchCompleted,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.width,
    this.height,
    this.color,
    this.colorBlendMode,
    this.fit,
    this.alignment = Alignment.center,
    this.repeat = ImageRepeat.noRepeat,
    this.centerSlice,
    this.matchTextDirection = false,
  })  : assert(controller?.duration != null || fps != null,
            '[controller] duration or [fps] must be specified'),
        assert(fps == null || fps > 0, 'fps must be greater than 0'),
        super(key: key);

  @override
  State<Gif> createState() => _GifState();
}

///
/// Works as a cache system for [Gif] and stores all the [ImageInfo] of rendered images.
///
@immutable
class GifCache {
  final Map<String, List<ImageInfo>> caches = {};

  /// Clears all the stored gifs from the cache.
  void clear() => caches.clear();

  /// Removes single gif from the cache.
  bool evict(Object key) => caches.remove(key) != null ? true : false;
}

class _GifState extends State<Gif> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// List of [ImageInfo] of every frame of this gif.
  List<ImageInfo> _frames = [];

  int _frameIndex = 0;

  /// Current rendered frame.
  ImageInfo? get _frame =>
      _frames.length > _frameIndex ? _frames[_frameIndex] : null;

  @override
  Widget build(BuildContext context) {
    final RawImage image = RawImage(
      image: _frame?.image,
      width: widget.width,
      height: widget.height,
      scale: _frame?.scale ?? 1.0,
      color: widget.color,
      colorBlendMode: widget.colorBlendMode,
      fit: widget.fit,
      alignment: widget.alignment,
      repeat: widget.repeat,
      centerSlice: widget.centerSlice,
      matchTextDirection: widget.matchTextDirection,
    );
    return widget.placeholder != null && _frame == null
        ? widget.placeholder!(context)
        : widget.excludeFromSemantics
            ? image
            : Semantics(
                container: widget.semanticLabel != null,
                image: true,
                label: widget.semanticLabel ?? '',
                child: image,
              );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadFrames().then((value) {
      if (widget.autostart == true) {
        _controller
          ..reset()
          ..forward();
      }
    });
  }

  @override
  void didUpdateWidget(Gif oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.removeListener(_listener);
      _controller = widget.controller ?? AnimationController(vsync: this);
      _controller.addListener(_listener);
    }
    if (widget.fps != oldWidget.fps) {
      _controller.duration = Duration(
        milliseconds: (_frames.length / widget.fps! * 1000).round(),
      );
    }
    if (widget.image != oldWidget.image) {
      _loadFrames().then((value) {
        if (widget.autostart == true) {
          _controller
            ..reset()
            ..forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_listener);
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? AnimationController(vsync: this);
    _controller.addListener(_listener);
  }

  /// Calculates the [_frameIndex] based on the [AnimationController] value.
  ///
  /// The calculation is based on the frames of the gif
  /// and the [Duration] of [AnimationController].
  void _listener() {
    if (_frames.isNotEmpty && mounted) {
      setState(() {
        _frameIndex = _frames.isEmpty
            ? 0
            : ((_frames.length - 1) * _controller.value).floor();
      });
    }
  }

  /// Fetches the frames with [_fetchFrames] and saves them into [_frames].
  ///
  /// When [_frames] is updated [onFetchCompleted] is called.
  Future<void> _loadFrames() async {
    List<ImageInfo> frames = await _fetchFrames(widget.image);
    if (!mounted) return;
    setState(() {
      _frames = frames;
      if (widget.fps != null) {
        _controller.duration = Duration(
          milliseconds: (_frames.length / widget.fps! * 1000).round(),
        );
      }
      if (widget.onFetchCompleted != null) {
        widget.onFetchCompleted!();
      }
    });
  }

  /// Fetches the single gif frames and saves them into the [GifCache] of [Gif]
  static Future<List<ImageInfo>> _fetchFrames(ImageProvider provider) async {
    String key = provider is NetworkImage
        ? provider.url
        : provider is AssetImage
            ? provider.assetName
            : provider is MemoryImage
                ? provider.bytes.toString()
                : "";

    if (Gif.cache.caches.containsKey(key)) {
      return Gif.cache.caches[key]!;
    }

    late final Uint8List bytes;

    if (provider is NetworkImage) {
      final Uri resolved = Uri.base.resolve(provider.url);
      final HttpClientRequest request = await _httpClient.getUrl(resolved);
      provider.headers?.forEach(
          (String name, String value) => request.headers.add(name, value));
      final HttpClientResponse response = await request.close();
      bytes = await consolidateHttpClientResponseBytes(response);
    } else if (provider is AssetImage) {
      AssetBundleImageKey key =
          await provider.obtainKey(const ImageConfiguration());
      bytes = (await key.bundle.load(key.name)).buffer.asUint8List();
    } else if (provider is FileImage) {
      bytes = await provider.file.readAsBytes();
    } else if (provider is MemoryImage) {
      bytes = provider.bytes;
    }

    // Removing ! gives compile time error on Flutter 2.5.3
    // ignore: unnecessary_non_null_assertion
    Codec codec = await PaintingBinding.instance!.instantiateImageCodec(bytes);
    List<ImageInfo> infos = [];

    for (int i = 0; i < codec.frameCount; i++) {
      FrameInfo frameInfo = await codec.getNextFrame();
      infos.add(ImageInfo(image: frameInfo.image));
    }

    Gif.cache.caches.putIfAbsent(key, () => infos);

    return infos;
  }
}
