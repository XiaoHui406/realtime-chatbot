import 'dart:convert';
import 'package:http/http.dart' as http;

import 'config.dart';

class ReferenceAudioInfo {
  final int id;
  final String name;
  final String tags;

  ReferenceAudioInfo({
    required this.id,
    required this.name,
    required this.tags,
  });

  factory ReferenceAudioInfo.fromJson(Map<String, dynamic> json) {
    return ReferenceAudioInfo(
      id: json['id'] as int,
      name: json['name'] as String,
      tags: json['tags'] as String,
    );
  }
}

class ApiService {
  final String baseUrl;

  ApiService({this.baseUrl = AppConfig.httpBaseUrl});

  Future<List<ReferenceAudioInfo>> getReferenceAudios() async {
    final response = await http.get(Uri.parse('$baseUrl/get_reference_audios'));
    if (response.statusCode != 200) {
      throw Exception('Failed to load reference audios: ${response.statusCode}');
    }
    final List<dynamic> jsonList = jsonDecode(response.body);
    return jsonList
        .map((item) => ReferenceAudioInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<String> uploadReferenceAudio({
    required String filePath,
    required String fileName,
    required String name,
    required String tags,
  }) async {
    final uri = Uri.parse('$baseUrl/upload_reference_audio')
        .replace(queryParameters: {'name': name, 'tags': tags});
    final request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('audio', filePath, filename: fileName));
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 200) {
      throw Exception('Failed to upload audio: ${response.statusCode} ${response.body}');
    }
    return response.body;
  }

  Future<String> setReferenceAudio(int audioId) async {
    final uri = Uri.parse('$baseUrl/set_reference_audio')
        .replace(queryParameters: {'audio_id': audioId.toString()});
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to set reference audio: ${response.statusCode}');
    }
    return response.body;
  }

  Future<String> deleteReferenceAudio(int audioId) async {
    final uri = Uri.parse('$baseUrl/delete_reference_audio')
        .replace(queryParameters: {'audio_id': audioId.toString()});
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to delete reference audio: ${response.statusCode}');
    }
    return response.body;
  }
}
