import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:blowfish/blowfish.dart';
import 'package:crypto/crypto.dart' as hash;
import 'dart:convert';
import 'deezer_service.dart';
import 'jiosaavn_service.dart';
import 'client_stream_service.dart';

/// Local HTTP proxy that streams Deezer audio with on-the-fly Blowfish
/// decryption. ExoPlayer connects to localhost and receives plain MP3 bytes
/// as they arrive from the Deezer CDN — no full-file download needed.
class DeezerProxy {
  static DeezerProxy? _instance;
  static DeezerProxy get instance => _instance ??= DeezerProxy._();
  DeezerProxy._();

  HttpServer? _server;
  int? _port;
  bool _starting = false;

  static const String _magicKey = 'g4el58wc0zvf9na1';
  static const int _blockSize = 2048;
  static final Uint8List _iv = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7]);
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// Ensure the local server is running. Returns the port.
  Future<int> ensureRunning() async {
    if (_port != null && _server != null) return _port!;
    if (_starting) {
      while (_starting) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _port!;
    }

    _starting = true;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      print('[DeezerProxy] Listening on port $_port');
      _server!.listen(_handleRequest);
      return _port!;
    } finally {
      _starting = false;
    }
  }

  /// URL that ExoPlayer should play to stream a track with live decryption.
  String streamUrl(String trackId) => 'http://127.0.0.1:$_port/stream/$trackId';

  bool get isRunning => _server != null && _port != null;

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers.set('Access-Control-Allow-Origin', '*');

    final path = request.uri.path;
    if (!path.startsWith('/stream/')) {
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }

    final trackId = path.substring('/stream/'.length);
    final title = request.uri.queryParameters['title'] ?? '';
    final artist = request.uri.queryParameters['artist'] ?? '';
    print(
        '[DeezerProxy] Stream request for trackId=$trackId title="$title" artist="$artist"');

    // Handle non-numeric IDs (e.g. iTunes US tracks or JioSaavn tracks)
    if (trackId.startsWith('itunes_') || trackId.startsWith('jio_')) {
      if (title.isNotEmpty) {
        final jioUrl = await JioSaavnService.getStreamUrl(title, artist);
        if (jioUrl != null && jioUrl.isNotEmpty) {
          print(
              '[DeezerProxy] ⚡ Direct JioSaavn CDN pipe for "$title" by "$artist"');
          await _pipeStream(request, jioUrl);
          return;
        }
      }
    }

    // Validate trackId — must be a positive integer (Deezer IDs are always positive)
    if (int.tryParse(trackId) == null || int.parse(trackId) <= 0) {
      // Try searching by title+artist on Deezer if available
      if (title.isNotEmpty) {
        print(
            '[DeezerProxy] Invalid trackId=$trackId, searching Deezer for title="$title" artist="$artist"');
        final resolved = await DeezerService.searchTrackId(title, artist);
        if (resolved != null) {
          print('[DeezerProxy] Resolved via search: trackId=$resolved');
          await _streamFromDeezer(request, resolved,
              title: title, artist: artist);
          return;
        }
      }

      // Check JioSaavn CDN before failing
      if (title.isNotEmpty) {
        final jioUrl = await JioSaavnService.getStreamUrl(title, artist);
        if (jioUrl != null && jioUrl.isNotEmpty) {
          print('[DeezerProxy] Piping JioSaavn CDN stream');
          await _pipeStream(request, jioUrl);
          return;
        }
      }
      print('[DeezerProxy] Invalid trackId: $trackId');
      request.response.statusCode = 400;
      await request.response.close();
      return;
    }

    try {
      await _streamFromDeezer(request, trackId, title: title, artist: artist);
    } catch (e) {
      print('[DeezerProxy] Error serving track $trackId: $e');
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _streamFromDeezer(
    HttpRequest request,
    String trackId, {
    String title = '',
    String artist = '',
  }) async {
    // Get CDN URL through DeezerService's cached auth + CDN cache
    final cdnUrl = await DeezerService.getCdnUrl(trackId);
    if (cdnUrl == null) {
      print(
          '[DeezerProxy] No Deezer CDN URL for trackId=$trackId (geo-blocked or invalid)');
      if (title.isNotEmpty) {
        final jioUrl = await JioSaavnService.getStreamUrl(title, artist);
        if (jioUrl != null && jioUrl.isNotEmpty) {
          print(
              '[DeezerProxy] ⚡ Geo-block fallback: Streaming JioSaavn CDN: $jioUrl');
          await _pipeStream(request, jioUrl);
          return;
        }

        try {
          final clientStream =
              await ClientStreamService.getAudioStream(title, artist);
          if (clientStream != null) {
            print(
                '[DeezerProxy] ⚡ Streaming on-device audio stream for "$title"');
            await _pipeByteStream(request, clientStream);
            return;
          }
        } catch (e) {
          print('[DeezerProxy] Client audio stream fallback error: $e');
        }
      }
      request.response.statusCode = 502;
      await request.response.close();
      return;
    }

    // Fetch from Deezer CDN and stream with on-the-fly decryption
    http.Client client = http.Client();
    http.StreamedResponse? streamedResponse;

    try {
      final cdnRequest = http.Request('GET', Uri.parse(cdnUrl));
      cdnRequest.headers['User-Agent'] = _ua;
      final resp = await client.send(cdnRequest).timeout(
            const Duration(seconds: 10),
          );
      if (resp.statusCode == 200) {
        streamedResponse = resp;
      } else {
        print(
            '[DeezerProxy] CDN returned ${resp.statusCode}, evicting cache...');
        client.close();
      }
    } catch (e) {
      print('[DeezerProxy] Error connecting to Deezer CDN: $e');
      client.close();
    }

    // If initial CDN URL was expired or failed, try fresh URL with re-auth
    if (streamedResponse == null) {
      DeezerService.evictCdnUrl(trackId);
      DeezerService.invalidateAuth();

      final freshCdnUrl = await DeezerService.getCdnUrl(trackId);
      if (freshCdnUrl != null && freshCdnUrl != cdnUrl) {
        try {
          final retryClient = http.Client();
          final retryReq = http.Request('GET', Uri.parse(freshCdnUrl));
          retryReq.headers['User-Agent'] = _ua;
          final retryResp = await retryClient
              .send(retryReq)
              .timeout(const Duration(seconds: 10));
          if (retryResp.statusCode == 200) {
            print('[DeezerProxy] ⚡ Fresh Deezer CDN stream connected!');
            await _pipeDecryptedStream(request, retryResp, retryClient, trackId);
            return;
          }
          retryClient.close();
        } catch (_) {}
      }

      // Geo-block or CDN failure fallback: JioSaavn or ClientStream
      if (title.isNotEmpty) {
        final jioUrl = await JioSaavnService.getStreamUrl(title, artist);
        if (jioUrl != null && jioUrl.isNotEmpty) {
          print(
              '[DeezerProxy] ⚡ Fallback after CDN error: Streaming JioSaavn CDN: $jioUrl');
          await _pipeStream(request, jioUrl);
          return;
        }

        try {
          final clientStream =
              await ClientStreamService.getAudioStream(title, artist);
          if (clientStream != null) {
            print(
                '[DeezerProxy] ⚡ Fallback after CDN error: Streaming on-device audio for "$title"');
            await _pipeByteStream(request, clientStream);
            return;
          }
        } catch (e) {
          print('[DeezerProxy] Client stream fallback error: $e');
        }
      }

      request.response.statusCode = 502;
      await request.response.close();
      return;
    }

    await _pipeDecryptedStream(request, streamedResponse, client, trackId);
  }

  Future<void> _pipeDecryptedStream(
    HttpRequest request,
    http.StreamedResponse streamedResponse,
    http.Client client,
    String trackId,
  ) async {
    request.response.headers.contentType = ContentType('audio', 'mpeg');

    final bfKey = _calculateBfKey(trackId);
    final bf = newBlowfish(List<int>.from(bfKey));

    int blockIndex = 0;
    Uint8List remainder = Uint8List(0);
    final completer = Completer<void>();

    streamedResponse.stream.listen(
      (chunk) {
        final data = remainder.isNotEmpty
            ? Uint8List.fromList([...remainder, ...chunk])
            : Uint8List.fromList(chunk);

        int offset = 0;
        while (offset + _blockSize <= data.length) {
          final block = data.sublist(offset, offset + _blockSize);
          final decrypted = _decryptBlock(bf, block, blockIndex);
          try {
            request.response.add(decrypted);
          } catch (_) {
            // Client closed connection (e.g. skip track)
            return;
          }
          offset += _blockSize;
          blockIndex++;
        }

        remainder = data.sublist(offset);
      },
      onDone: () async {
        if (remainder.isNotEmpty) {
          final decrypted = _decryptBlock(bf, remainder, blockIndex);
          try {
            request.response.add(decrypted);
          } catch (_) {}
        }
        client.close();
        try {
          await request.response.close();
        } catch (_) {}
        if (!completer.isCompleted) completer.complete();
      },
      onError: (e) async {
        print('[DeezerProxy] CDN stream error: $e');
        client.close();
        try {
          await request.response.close();
        } catch (_) {}
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    await completer.future;
  }

  Uint8List _decryptBlock(Blowfish bf, Uint8List block, int blockIndex) {
    if (blockIndex % 3 == 0) {
      final paddedSize = ((block.length + 7) ~/ 8) * 8;
      final padded = Uint8List(paddedSize);
      padded.setAll(0, block);
      final decryptedBlock = bf.decryptCBC(
        List<int>.from(padded),
        List<int>.from(_iv),
        applyPadding: false,
      );
      return Uint8List.fromList(decryptedBlock.sublist(0, block.length));
    } else {
      return block;
    }
  }

  static Uint8List _calculateBfKey(String trackId) {
    final md5Digest = hash.md5.convert(utf8.encode(trackId));
    final md5Hex =
        md5Digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final key = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      final first = md5Hex.codeUnitAt(i);
      final second = md5Hex.codeUnitAt(i + 16);
      final magic = _magicKey.codeUnitAt(i);
      key[i] = (first ^ second ^ magic) & 0xFF;
    }
    return key;
  }

  Future<void> _pipeStream(HttpRequest request, String url) async {
    try {
      final client = http.Client();
      final cdnRequest = http.Request('GET', Uri.parse(url));
      cdnRequest.headers['User-Agent'] = _ua;

      final range = request.headers.value('range');
      if (range != null) {
        cdnRequest.headers['Range'] = range;
      }

      final streamedResponse = await client.send(cdnRequest).timeout(
            const Duration(seconds: 15),
          );

      request.response.statusCode = streamedResponse.statusCode;
      streamedResponse.headers.forEach((k, v) {
        final kLower = k.toLowerCase();
        if (kLower == 'content-length' ||
            kLower == 'content-type' ||
            kLower == 'content-range' ||
            kLower == 'accept-ranges') {
          request.response.headers.set(k, v);
        }
      });

      await request.response.addStream(streamedResponse.stream);
      await request.response.close();
      client.close();
    } catch (e) {
      print('[DeezerProxy] Direct pipe error: $e');
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _pipeByteStream(
      HttpRequest request, ClientAudioStream stream) async {
    try {
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType('audio', 'webm');
      if (stream.size > 0) {
        request.response.headers.contentLength = stream.size;
      }
      await request.response.addStream(stream.byteStream);
      await request.response.close();
    } catch (e) {
      print('[DeezerProxy] Byte stream pipe error: $e');
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await _server?.close();
    _server = null;
    _port = null;
  }
}
