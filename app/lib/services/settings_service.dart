import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static final SettingsService _instance = SettingsService._();
  factory SettingsService() => _instance;
  SettingsService._();

  static const _apiKeyKey = 'auth_api_key';

  String _apiKey = '';

  String get apiKey => _apiKey;

  bool get hasApiKey => _apiKey.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(_apiKeyKey) ?? '';
  }

  Future<void> setApiKey(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, value);
    _apiKey = value;
  }
}
