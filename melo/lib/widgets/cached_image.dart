import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// A disk-backed replacement for `Image.network`.
///
/// Renders the image from a local file when available (works fully offline),
/// otherwise downloads it, persists it to disk, then renders it. Subsequent
/// opens — even after an app restart with no internet — show the cached image.
class CachedImage extends StatefulWidget {
  const CachedImage(
    this.imageUrl, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.errorBuilder,
    this.filterQuality = FilterQuality.low,
    this.placeholder,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final ImageErrorWidgetBuilder? errorBuilder;
  final FilterQuality filterQuality;
  final Widget? placeholder;

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  File? _file;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loading = false;
      return;
    }
    if (widget.imageUrl.trim().isEmpty) {
      _loading = false;
      _failed = true;
      return;
    }
    // Synchronous memory check: if file was already resolved, render immediately on frame 1
    final cached = CachedImageStore.memFileFor(widget.imageUrl);
    if (cached != null) {
      _file = cached;
      _loading = false;
    } else {
      _resolve();
    }
  }

  @override
  void didUpdateWidget(CachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      if (kIsWeb) {
        _loading = false;
        return;
      }
      final clean = widget.imageUrl.trim();
      if (clean.isEmpty) {
        _file = null;
        _loading = false;
        _failed = true;
        return;
      }
      final cached = CachedImageStore.memFileFor(clean);
      if (cached != null) {
        _file = cached;
        _loading = false;
        _failed = false;
      } else {
        // Reset file to prevent neighboring items from showing the wrong image
        // during ListView widget recycling.
        _file = null;
        _loading = true;
        _failed = false;
        _resolve();
      }
    }
  }

  Future<void> _resolve() async {
    if (kIsWeb) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final cleanUrl = widget.imageUrl.trim();
    if (cleanUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _file = null;
          _loading = false;
          _failed = true;
        });
      }
      return;
    }
    if (cleanUrl.startsWith('asset/')) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
      return;
    }
    final file = await CachedImageStore.fileFor(cleanUrl);
    if (!mounted || widget.imageUrl.trim() != cleanUrl) return;
    if (await file.exists() && (await file.length()) > 200) {
      CachedImageStore.rememberFile(cleanUrl, file);
      if (mounted && widget.imageUrl.trim() == cleanUrl) {
        setState(() {
          _file = file;
          _loading = false;
          _failed = false;
        });
      }
      return;
    }
    // Not on disk yet — try to fetch and persist.
    try {
      await CachedImageStore.download(cleanUrl, file);
      if (!mounted || widget.imageUrl.trim() != cleanUrl) return;
      CachedImageStore.rememberFile(cleanUrl, file);
      if (mounted && widget.imageUrl.trim() == cleanUrl) {
        setState(() {
          _file = file;
          _loading = false;
          _failed = false;
        });
      }
    } catch (_) {
      if (!mounted || widget.imageUrl.trim() != cleanUrl) return;
      if (mounted && widget.imageUrl.trim() == cleanUrl) {
        setState(() {
          _file = null;
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      if (widget.imageUrl.startsWith('asset/')) {
        return Image.asset(
          widget.imageUrl,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          alignment: widget.alignment,
          filterQuality: widget.filterQuality,
          errorBuilder: widget.errorBuilder,
        );
      }
      return Image.network(
        widget.imageUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        alignment: widget.alignment,
        filterQuality: widget.filterQuality,
        errorBuilder: widget.errorBuilder,
      );
    }
    if (widget.imageUrl.startsWith('asset/')) {
      return Image.asset(
        widget.imageUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        alignment: widget.alignment,
        filterQuality: widget.filterQuality,
        errorBuilder: widget.errorBuilder,
      );
    }

    if (_loading) {
      return widget.placeholder ??
          Container(
              width: widget.width,
              height: widget.height,
              color: const Color(0xFF2A2A2A));
    }

    final file = _file;
    if (file != null && file.existsSync()) {
      return Image.file(
        file,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        alignment: widget.alignment,
        filterQuality: widget.filterQuality,
        errorBuilder: widget.errorBuilder,
      );
    }

    if (_failed) {
      return widget.errorBuilder
              ?.call(context, Exception('image unavailable'), null) ??
          const SizedBox.shrink();
    }

    return const SizedBox.shrink();
  }
}

/// Persists network images to a cache directory keyed by URL hash.
class CachedImageStore {
  static Directory? _dir;
  static final Map<String, Future<void>> _inFlight = {};
  static final Map<String, File> _memCache = {};

  static File? memFileFor(String url) => _memCache[url];

  static void rememberFile(String url, File file) {
    _memCache[url] = file;
  }

  static Future<Directory> _getDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/image_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  static String _hash(String url) {
    return md5.convert(utf8.encode(url.trim())).toString();
  }

  static Future<File> fileFor(String url) async {
    final dir = await _getDir();
    return File('${dir.path}/${_hash(url)}.img');
  }

  static Future<void> download(String url, File file) async {
    // Dedupe concurrent downloads of the same URL.
    final existing = _inFlight[url];
    if (existing != null) {
      await existing;
      return;
    }
    final future = _downloadInner(url, file);
    _inFlight[url] = future;
    try {
      await future;
    } finally {
      _inFlight.remove(url);
    }
  }

  static Future<void> _downloadInner(String url, File file) async {
    final response =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Image download failed: ${response.statusCode}');
    }
    if (response.bodyBytes.length <= 200) {
      throw Exception(
          'Downloaded image file too small: ${response.bodyBytes.length} bytes');
    }
    final tmpFile = File('${file.path}.tmp');
    await tmpFile.writeAsBytes(response.bodyBytes, flush: true);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    await tmpFile.rename(file.path);
  }
}
