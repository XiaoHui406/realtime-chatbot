import 'package:shared_preferences/shared_preferences.dart';

enum CallMode { normal, live2d }

class SettingsService {
  static final SettingsService _instance = SettingsService._();
  factory SettingsService() => _instance;
  SettingsService._();

  static const _apiKeyKey = 'auth_api_key';
  static const _callModeKey = 'call_mode';

  String _apiKey = '';
  CallMode _callMode = CallMode.normal;

  String get apiKey => _apiKey;
  bool get hasApiKey => _apiKey.isNotEmpty;
  CallMode get callMode => _callMode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(_apiKeyKey) ?? '';
    final raw = prefs.getString(_callModeKey);
    _callMode = raw == 'live2d' ? CallMode.live2d : CallMode.normal;
  }

  Future<void> setApiKey(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, value);
    _apiKey = value;
  }

  Future<void> setCallMode(CallMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_callModeKey, mode == CallMode.live2d ? 'live2d' : 'normal');
    _callMode = mode;
  }
}
