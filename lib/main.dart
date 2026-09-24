import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:vibration/vibration.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AttendanceProvider(),
      child: const ExamAttendanceApp(),
    ),
  );
}

class Student {
  final String code;
  final String name;
  final String grade;
  final String group;
  bool isPresent;
  String? attendanceTime;

  Student({
    required this.code,
    required this.name,
    required this.grade,
    required this.group,
    this.isPresent = false,
    this.attendanceTime,
  });
}

class AttendanceProvider extends ChangeNotifier {
  List<Student> _students = [];
  List<Student> get students => _students;

  int get totalCount => _students.length;
  int get presentCount => _students.where((s) => s.isPresent).length;

  Future<void> importStudentsFromExcel() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );

    if (result != null && result.files.single.path != null) {
      var bytes = File(result.files.single.path!).readAsBytesSync();
      var excel = excel_lib.Excel.decodeBytes(bytes);

      _students.clear();
      for (var table in excel.tables.keys) {
        var rows = excel.tables[table]?.rows;
        if (rows == null) continue;

        for (int i = 1; i < rows.length; i++) {
          var row = rows[i];
          if (row.length >= 4) {
            String code = row[0]?.value?.toString().trim() ?? '';
            String name = row[1]?.value?.toString().trim() ?? '';
            String grade = row[2]?.value?.toString().trim() ?? '';
            String group = row[3]?.value?.toString().trim() ?? '';

            if (code.isNotEmpty) {
              _students.add(Student(
                code: code,
                name: name,
                grade: grade,
                group: group,
              ));
            }
          }
        }
      }
      notifyListeners();
    }
  }

  bool markAttendance(String code) {
    int index = _students.indexWhere((s) => s.code == code);
    if (index != -1 && !_students[index].isPresent) {
      _students[index].isPresent = true;
      _students[index].attendanceTime = DateFormat('hh:mm:ss a').format(DateTime.now());
      notifyListeners();
      Vibration.vibrate(duration: 100);
      return true;
    }
    return false;
  }

  Future<void> exportToExcel(BuildContext context) async {
    if (_students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد بيانات طلاب لتصديرها!')),
      );
      return;
    }

    var excel = excel_lib.Excel.createExcel();
    excel_lib.Sheet sheetObject = excel['الحضور'];
    excel.delete('Sheet1');

    sheetObject.appendRow([
      excel_lib.TextCellValue('كود الطالب'),
      excel_lib.TextCellValue('اسم الطالب'),
      excel_lib.TextCellValue('الصف الدراسي'),
      excel_lib.TextCellValue('المجموعة'),
      excel_lib.TextCellValue('حالة الحضور'),
      excel_lib.TextCellValue('وقت الحضور'),
    ]);

    for (var student in _students) {
      sheetObject.appendRow([
        excel_lib.TextCellValue(student.code),
        excel_lib.TextCellValue(student.name),
        excel_lib.TextCellValue(student.grade),
        excel_lib.TextCellValue(student.group),
        excel_lib.TextCellValue(student.isPresent ? 'حاضر' : 'غائب'),
        excel_lib.TextCellValue(student.attendanceTime ?? '-'),
      ]);
    }

    var fileBytes = excel.save();
    if (fileBytes != null) {
      final fileName = "حضور_الطلاب_${DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now())}.xlsx";

      // 1. تحديد مجلد Downloads أو المجلد العام
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
        if (!downloadsDir.existsSync()) {
          downloadsDir = await getExternalStorageDirectory();
        }
      } else {
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      final filePath = "${downloadsDir?.path}/$fileName";
      final file = File(filePath);
      await file.writeAsBytes(fileBytes);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ الملف في مجلد التحميلات:\n$fileName'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }

      // 2. فتح نافذة المشاركة المباشرة (الواتساب / الملفات)
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'تقرير حضور الطلاب - $fileName',
      );
    }
  }
}

class ExamAttendanceApp extends StatelessWidget {
  const ExamAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'نظام حضور الامتحانات',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        fontFamily: 'Roboto',
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AttendanceProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('نظام حضور الامتحانات'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text('إجمالي الطلاب', style: TextStyle(fontSize: 16)),
                        Text('${provider.totalCount}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo)),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('تم حضورهم', style: TextStyle(fontSize: 16)),
                        Text('${provider.presentCount}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.indigo.shade100,
                foregroundColor: Colors.indigo.shade900,
              ),
              onPressed: () => provider.importStudentsFromExcel(),
              icon: const Icon(Icons.file_upload),
              label: const Text('استيراد ملف Excel الطلاب', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 15),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
              ),
              onPressed: provider.totalCount == 0
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ScannerScreen()),
                      );
                    },
              icon: const Icon(Icons.camera_alt),
              label: const Text('بدء مسح الحضور (الكاميرا)', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 15),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () => provider.exportToExcel(context),
              icon: const Icon(Icons.file_download),
              label: const Text('تصدير ملف Excel النهائي', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: provider.students.length,
                itemBuilder: (context, index) {
                  final student = provider.students[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: student.isPresent ? Colors.green : Colors.grey.shade300,
                      child: Icon(
                        student.isPresent ? Icons.check : Icons.person,
                        color: student.isPresent ? Colors.white : Colors.grey,
                      ),
                    ),
                    title: Text(student.name),
                    subtitle: Text('${student.code} | ${student.grade} - ${student.group}'),
                    trailing: Text(
                      student.isPresent ? (student.attendanceTime ?? '') : 'غائب',
                      style: TextStyle(
                        color: student.isPresent ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AttendanceProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(title: const Text('مسح الباركود')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_isProcessing) return;

          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            final String? rawCode = barcode.rawValue;
            if (rawCode != null && rawCode.isNotEmpty) {
              setState(() => _isProcessing = true);

              bool success = provider.markAttendance(rawCode.trim());

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success ? 'تم تسجيل حضور الطالب: $rawCode' : 'الكود غير موجود أو تم تسجيله سابقاً!',
                  ),
                  backgroundColor: success ? Colors.green : Colors.red,
                  duration: const Duration(seconds: 1),
                ),
              );

              Future.delayed(const Duration(milliseconds: 1500), () {
                if (mounted) {
                  setState(() => _isProcessing = false);
                }
              });
              break;
            }
          }
        },
      ),
    );
  }
}
