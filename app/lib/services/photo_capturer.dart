import 'package:flutter/material.dart';
import '../pages/camera_capture_page.dart';

class PhotoCapturer {
  static Future<String?> capture(BuildContext context) async {
    return await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const CameraCapturePage()),
    );
  }
}
