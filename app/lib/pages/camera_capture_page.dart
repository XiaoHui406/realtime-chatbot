import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({super.key});

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage> {
  CameraController? _controller;
  bool _initialized = false;
  bool _capturing = false;
  Size? _previewSize;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _pop(null);
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _controller = CameraController(camera, ResolutionPreset.medium);
      await _controller!.initialize();
      _previewSize = _controller!.value.previewSize!;
      if (mounted) setState(() => _initialized = true);
    } catch (_) {
      _pop(null);
    }
  }

  Future<void> _capture() async {
    if (_capturing || _controller == null) return;
    setState(() => _capturing = true);
    try {
      final photo = await _controller!.takePicture();
      await _controller!.dispose();
      final bytes = await photo.readAsBytes();
      final base64 = _encode(bytes);
      _pop(base64);
    } catch (_) {
      await _controller?.dispose();
      _pop(null);
    }
  }

  String _encode(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return base64Encode(bytes);

    const maxSize = 1280;
    final out = decoded.width > maxSize || decoded.height > maxSize
        ? img.copyResize(
            decoded,
            width: (decoded.width *
                    math.min(maxSize / decoded.width, maxSize / decoded.height))
                .round(),
            height: (decoded.height *
                    math.min(maxSize / decoded.width, maxSize / decoded.height))
                .round(),
          )
        : decoded;

    return base64Encode(img.encodeJpg(out, quality: 75));
  }

  void _pop(String? result) {
    if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: _previewSize!.height,
                height: _previewSize!.width,
                child: CameraPreview(_controller!),
              ),
            ),
          ),
          Positioned(
            top: 48,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
              onPressed: () {
                _controller?.dispose();
                _pop(null);
              },
            ),
          ),
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _capturing ? null : _capture,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: _capturing
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
