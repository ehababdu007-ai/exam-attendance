import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// إعدادات قابلة للتعديل من داخل التطبيق بدون إعادة بناء (Recompile).
class SettingsProvider extends ChangeNotifier {
  static const String _keyWebAppUrl = 'webapp_url';
  static const String _keySheetViewUrl = 'sheet_view_url';

  // ضع هنا رابط Google Apps Script الافتراضي الصحيح الخاص بك.
  // ملاحظة: الرابط الأصلي في المستند المرفق كان تالفاً (يحتوي على صياغة
  // ماركداون [text](url) بالخطأ)، لذا لن يعمل كما هو. يمكنك ضبط الرابط
  // الصحيح من شاشة الإعدادات داخل التطبيق فوراً دون تعديل الكود.
  static const String defaultWebAppUrl =
      'https://script.google.com/macros/s/REPLACE_WITH_YOUR_DEPLOYMENT_ID/exec';

  String _webAppUrl = defaultWebAppUrl;
  String _sheetViewUrl = '';
  bool _isLoaded = false;

  String get webAppUrl => _webAppUrl;
  String get sheetViewUrl => _sheetViewUrl;
  bool get isLoaded => _isLoaded;
  bool get hasSheetViewUrl => _sheetViewUrl.trim().isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _webAppUrl = prefs.getString(_keyWebAppUrl) ?? defaultWebAppUrl;
    _sheetViewUrl = prefs.getString(_keySheetViewUrl) ?? '';
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> updateWebAppUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    _webAppUrl = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWebAppUrl, trimmed);
    notifyListeners();
  }

  Future<void> updateSheetViewUrl(String url) async {
    _sheetViewUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySheetViewUrl, _sheetViewUrl);
    notifyListeners();
  }
}
