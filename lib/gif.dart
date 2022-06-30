/*
  author: Pierluigi Zagaria
  email: pierluigizagaria@gmail.com
  time: 2019-7-26 3:30
*/

library gif;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class GifCache {
  final Map<String, List<ImageInfo>> caches = {};

  void clear() => caches.clear();

  bool evict(Object key) => caches.remove(key) != null ? true : false;
}

class Gif extends StatefulWidget {
  const Gif({
    Key? key,
    required this.image,
    required this.controller,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.width,
    this.height,
    this.placeholder,
    this.onFetchCompleted,
    this.color,
    this.colorBlendMode,
    this.fit,
    this.alignment = Alignment.center,
    this.repeat = ImageRepeat.noRepeat,
    this.centerSlice,
    this.matchTextDirection = false,
  }) : super(key: key);

  final VoidCallback? onFetchCompleted;
  final Widget Function(BuildContext context)? placeholder;
  final AnimationController controller;
  final ImageProvider image;
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

  @override
  State<Gif> createState() => _GifState();

  static GifCache cache = GifCache();
}

class _GifState extends State<Gif> {
  List<ImageInfo> _frames = [];
  int _frameIndex = 0;

  ImageInfo? get _frame => _frames.length > _frameIndex ? _frames[_frameIndex] : null;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_listener);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_listener);
    super.dispose();
  }

  @override
  void didUpdateWidget(Gif oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) {
      _loadFrames();
    }
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_listener);
      widget.controller.addListener(_listener);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadFrames();
  }

  void _loadFrames() async {
    List<ImageInfo> frames = await _fetchFrames(widget.image);
    if (!mounted) return;
    setState(() {
      _frames = frames;
      if (widget.onFetchCompleted != null) {
        widget.onFetchCompleted!();
      }
    });
  }

  void _listener() {
    if (_frames.isNotEmpty && mounted) {
      setState(() {
        _frameIndex =
            _frames.isEmpty ? 0 : ((_frames.length - 1) * widget.controller.value).floor();
      });
    }
  }

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
}

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

Future<List<ImageInfo>> _fetchFrames(ImageProvider provider) async {
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
    provider.headers?.forEach((String name, String value) => request.headers.add(name, value));
    final HttpClientResponse response = await request.close();
    bytes = await consolidateHttpClientResponseBytes(response);
  } else if (provider is AssetImage) {
    AssetBundleImageKey key = await provider.obtainKey(const ImageConfiguration());
    bytes = (await key.bundle.load(key.name)).buffer.asUint8List();
  } else if (provider is FileImage) {
    bytes = await provider.file.readAsBytes();
  } else if (provider is MemoryImage) {
    bytes = provider.bytes;
  }

  Codec codec = await PaintingBinding.instance!.instantiateImageCodec(bytes);
  List<ImageInfo> infos = [];

  for (int i = 0; i < codec.frameCount; i++) {
    FrameInfo frameInfo = await codec.getNextFrame();
    infos.add(ImageInfo(image: frameInfo.image));
  }

  Gif.cache.caches.putIfAbsent(key, () => infos);

  return infos;
}
