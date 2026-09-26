import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/attendance_provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _webAppController;
  late final TextEditingController _sheetViewController;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _webAppController = TextEditingController(text: settings.webAppUrl);
    _sheetViewController = TextEditingController(text: settings.sheetViewUrl);
  }

  @override
  void dispose() {
    _webAppController.dispose();
    _sheetViewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const Text(
              'رابط Google Apps Script (WebApp)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _webAppController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'https://script.google.com/macros/s/xxxx/exec',
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 24),
            const Text(
              'رابط عرض شيت جوجل (اختياري - لزر المعاينة داخل التطبيق)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _sheetViewController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'https://docs.google.com/spreadsheets/d/xxxx/pubhtml',
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('حفظ الإعدادات'),
                onPressed: () async {
                  final urlChanged = _webAppController.text.trim() != settings.webAppUrl;
                  await settings.updateWebAppUrl(_webAppController.text);
                  await settings.updateSheetViewUrl(_sheetViewController.text);
                  if (!context.mounted) return;
                  if (urlChanged) {
                    // جلب فوري بالرابط الجديد بدل انتظار ضغط تحديث يدوي لاحقاً
                    context.read<AttendanceProvider>().fetchStudentsFromSheet();
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حفظ الإعدادات بنجاح ✅')),
                  );
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
