import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/attendance_provider.dart';
import '../providers/settings_provider.dart';
import '../services/export_service.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';
import 'sheet_webview_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AttendanceProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('حضور الامتحانات', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          if (settings.hasSheetViewUrl)
            IconButton(
              icon: const Icon(Icons.table_chart),
              tooltip: 'معاينة شيت جوجل',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SheetWebViewScreen(url: settings.sheetViewUrl),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'تصدير تقرير CSV',
            onPressed: provider.presentCount == 0
                ? null
                : () => ExportService.exportPresentStudents(provider.students),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'الإعدادات',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث البيانات من الشيت',
            onPressed: () => provider.fetchStudentsFromSheet(),
          ),
        ],
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (!provider.isConnected || provider.pendingSyncCount > 0)
                  Container(
                    width: double.infinity,
                    color: Colors.amber.shade100,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.sync_problem, color: Colors.amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            provider.pendingSyncCount > 0
                                ? 'يوجد (${provider.pendingSyncCount}) حضور معلق للمزامنة'
                                : 'لا يوجد اتصال بالسيرفر حالياً',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => provider.syncPending(),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800),
                          child: const Text('مزامنة الآن', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: 'إجمالي الطلاب',
                          value: provider.totalCount,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(
                          label: 'تم حضورهم',
                          value: provider.presentCount,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ScannerScreen()),
                      ),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('فتح كاميرا المسح والتحضير',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green, foregroundColor: Colors.white),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: TextField(
                    onChanged: (val) => provider.setSearchQuery(val),
                    decoration: InputDecoration(
                      hintText: 'بحث باسم الطالب أو الكود...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                Expanded(
                  child: provider.filteredStudents.isEmpty
                      ? const Center(child: Text('لا يوجد طلاب مسجلون حالياً'))
                      : ListView.builder(
                          itemCount: provider.filteredStudents.length,
                          itemBuilder: (context, index) {
                            final student = provider.filteredStudents[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      student.isSynced ? Colors.green : Colors.amber,
                                  child: Icon(
                                    student.isSynced ? Icons.check : Icons.cloud_upload,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(student.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle:
                                    Text('كود: ${student.code} | ${student.grade} - ${student.timeGroup}'),
                                trailing: Text(
                                  student.attendanceTime,
                                  style: const TextStyle(
                                      color: Colors.green, fontWeight: FontWeight.bold),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final MaterialColor color;

  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 16)),
            Text('$value',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}
