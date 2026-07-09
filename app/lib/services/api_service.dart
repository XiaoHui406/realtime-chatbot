import 'dart:convert';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'settings_service.dart';

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

  Map<String, String> get _authHeaders {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final apiKey = SettingsService().apiKey;
    if (apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    return headers;
  }

  Future<List<ReferenceAudioInfo>> getReferenceAudios() async {
    final response = await http.get(Uri.parse('$baseUrl/reference_audio'), headers: _authHeaders);
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
    final uri = Uri.parse('$baseUrl/reference_audio')
        .replace(queryParameters: {'name': name, 'tags': tags});
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = _authHeaders['Authorization'] ?? '';
    request.files.add(await http.MultipartFile.fromPath('audio', filePath, filename: fileName));
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 200) {
      throw Exception('Failed to upload audio: ${response.statusCode} ${response.body}');
    }
    return response.body;
  }

  Future<String> setReferenceAudio(int audioId) async {
    final uri = Uri.parse('$baseUrl/reference_audio/$audioId/activate');
    final response = await http.put(uri, headers: _authHeaders);
    if (response.statusCode != 200) {
      throw Exception('Failed to set reference audio: ${response.statusCode}');
    }
    return response.body;
  }

  Future<String> editReferenceAudio(int audioId, String name, String tags) async {
    final uri = Uri.parse('$baseUrl/reference_audio/$audioId')
        .replace(queryParameters: {'name': name, 'tags': tags});
    final response = await http.put(uri, headers: _authHeaders);
    if (response.statusCode != 200) {
      throw Exception('Failed to edit reference audio: ${response.statusCode}');
    }
    return response.body;
  }

  Future<String> deleteReferenceAudio(int audioId) async {
    final uri = Uri.parse('$baseUrl/reference_audio/$audioId');
    final response = await http.delete(uri, headers: _authHeaders);
    if (response.statusCode != 200) {
      throw Exception('Failed to delete reference audio: ${response.statusCode}');
    }
    return response.body;
  }

  Future<List<ChatbotSessionInfo>> getSessions({int limit = 50, int offset = 0}) async {
    final uri = Uri.parse('$baseUrl/chatbot_session')
        .replace(queryParameters: {'limit': limit.toString(), 'offset': offset.toString()});
    final response = await http.get(uri, headers: _authHeaders);
    if (response.statusCode != 200) {
      throw Exception('Failed to get sessions: ${response.statusCode}');
    }
    final List<dynamic> jsonList = jsonDecode(response.body);
    return jsonList
        .map((item) => ChatbotSessionInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ChatbotSessionInfo> createSession({String? title, String? initialPrompt}) async {
    final uri = Uri.parse('$baseUrl/chatbot_session');
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (initialPrompt != null) body['initial_prompt'] = initialPrompt;
    final response = await http.post(uri, body: jsonEncode(body), headers: _authHeaders);
    if (response.statusCode != 200) {
      throw Exception('Failed to create session: ${response.statusCode}');
    }
    return ChatbotSessionInfo.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<String> editSession(int sessionId, String title) async {
    final uri = Uri.parse('$baseUrl/chatbot_session/$sessionId')
        .replace(queryParameters: {'title': title});
    final response = await http.put(uri, headers: _authHeaders);
    if (response.statusCode != 200) {
      throw Exception('Failed to edit session: ${response.statusCode}');
    }
    return response.body;
  }

  Future<String> deleteSession(int sessionId) async {
    final uri = Uri.parse('$baseUrl/chatbot_session/$sessionId');
    final response = await http.delete(uri, headers: _authHeaders);
    if (response.statusCode != 200) {
      throw Exception('Failed to delete session: ${response.statusCode}');
    }
    return response.body;
  }

  Future<List<ChatbotMessageInfo>> getSessionMessages(int sessionId) async {
    final uri = Uri.parse('$baseUrl/chatbot_session/$sessionId/messages');
    final response = await http.get(uri, headers: _authHeaders);
    if (response.statusCode != 200) {
      throw Exception('Failed to get messages: ${response.statusCode}');
    }
    final List<dynamic> jsonList = jsonDecode(response.body);
    return jsonList
        .map((item) => ChatbotMessageInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}

class ChatbotSessionInfo {
  final int id;
  final String? title;
  final String createdAt;
  final String updatedAt;

  ChatbotSessionInfo({
    required this.id,
    this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChatbotSessionInfo.fromJson(Map<String, dynamic> json) {
    return ChatbotSessionInfo(
      id: json['id'] as int,
      title: json['title'] as String?,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }
}

class ChatbotMessageInfo {
  final int id;
  final int sessionId;
  final String role;
  final dynamic content;
  final String? toolCallId;
  final String createdAt;

  ChatbotMessageInfo({
    required this.id,
    required this.sessionId,
    required this.role,
    this.content,
    this.toolCallId,
    required this.createdAt,
  });

  factory ChatbotMessageInfo.fromJson(Map<String, dynamic> json) {
    return ChatbotMessageInfo(
      id: json['id'] as int,
      sessionId: json['session_id'] as int,
      role: json['role'] as String,
      content: json['content'],
      toolCallId: json['tool_call_id'] as String?,
      createdAt: json['created_at'] as String,
    );
  }

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isSystem => role == 'system';

  String get displayContent {
    if (content == null) return '';
    if (content is String) return content as String;
    if (content is List) {
      return (content as List)
          .map((part) => (part is Map<String, dynamic>) ? part['text'] as String? ?? '' : '')
          .join('');
    }
    return content.toString();
  }
}
