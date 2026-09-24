import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Row;
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => ExamController(),
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: HomeScreen(),
      ),
    ),
  );
}

class Student {
  final String code;
  final String name;
  final String grade;
  final String group;

  Student({required this.code, required this.name, required this.grade, required this.group});
}

class AttendanceRecord {
  final String studentCode;
  final String timestamp;
  bool isRevoked;

  AttendanceRecord({required this.studentCode, required this.timestamp, this.isRevoked = false});
}

enum ScanResultType { success, duplicate, notFound }

class ScanFeedback {
  final ScanResultType type;
  final String message;
  final Student? student;
  final String? extraInfo;

  ScanFeedback({required this.type, required this.message, this.student, this.extraInfo});
}

class ExamController extends ChangeNotifier {
  Map<String, Student> _studentsMap = {};
  Map<String, AttendanceRecord> _attendanceMap = {};
  List<String> _scanHistoryStack = [];

  Student? lastScannedStudent;
  String? lastScanTime;
  File? originalFile;
  int codeColIdx = 0;

  int get totalAttended => _attendanceMap.values.where((r) => !r.isRevoked).length;
  bool get hasData => _studentsMap.isNotEmpty;

  void setStudents(List<Student> students, File file, int codeIdx) {
    _studentsMap = {for (var s in students) s.code: s};
    originalFile = file;
    codeColIdx = codeIdx;
    notifyListeners();
  }

  ScanFeedback processBarcode(String code) {
    String cleanCode = code.trim();

    if (!_studentsMap.containsKey(cleanCode)) {
      return ScanFeedback(
        type: ScanResultType.notFound,
        message: "الكود غير موجود بملف الطلاب",
        extraInfo: "الكود: $cleanCode",
      );
    }

    Student student = _studentsMap[cleanCode]!;

    if (_attendanceMap.containsKey(cleanCode) && !_attendanceMap[cleanCode]!.isRevoked) {
      var existingRecord = _attendanceMap[cleanCode]!;
      return ScanFeedback(
        type: ScanResultType.duplicate,
        message: "تم تسجيل الحضور سابقاً",
        student: student,
        extraInfo: "وقت التسجيل الأول: ${existingRecord.timestamp}",
      );
    }

    String currentTime = DateFormat('HH:mm:ss').format(DateTime.now());
    _attendanceMap[cleanCode] = AttendanceRecord(studentCode: cleanCode, timestamp: currentTime);
    _scanHistoryStack.add(cleanCode);

    lastScannedStudent = student;
    lastScanTime = currentTime;

    notifyListeners();

    return ScanFeedback(
      type: ScanResultType.success,
      message: "تم تسجيل الحضور بنجاح",
      student: student,
      extraInfo: currentTime,
    );
  }

  bool undoLastScan() {
    if (_scanHistoryStack.isEmpty) return false;
    String lastCode = _scanHistoryStack.removeLast();
    if (_attendanceMap.containsKey(lastCode)) {
      _attendanceMap[lastCode]!.isRevoked = true;
      if (_scanHistoryStack.isNotEmpty) {
        String prevCode = _scanHistoryStack.last;
        lastScannedStudent = _studentsMap[prevCode];
        lastScanTime = _attendanceMap[prevCode]?.timestamp;
      } else {
        lastScannedStudent = null;
        lastScanTime = null;
      }
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<String?> exportExcel() async {
    if (originalFile == null) return null;
    var bytes = originalFile!.readAsBytesSync();
    var excel = Excel.decodeBytes(bytes);
    String sheetName = excel.tables.keys.first;
    var sheet = excel.tables[sheetName];
    if (sheet == null) return null;

    int attendanceColIdx = sheet.maxColumns;
    var headerRow = sheet.rows.first;
    for (int col = 0; col < headerRow.length; col++) {
      if (headerRow[col]?.value?.toString().trim() == "وقت الحضور") {
        attendanceColIdx = col;
        break;
      }
    }

    if (attendanceColIdx == sheet.maxColumns) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: attendanceColIdx, rowIndex: 0)).value = TextCellValue("وقت الحضور");
    }

    for (int rowIdx = 1; rowIdx < sheet.rows.length; rowIdx++) {
      var row = sheet.rows[rowIdx];
      if (row.length <= codeColIdx) continue;
      String studentCode = row[codeColIdx]?.value?.toString().trim() ?? '';
      if (_attendanceMap.containsKey(studentCode) && !_attendanceMap[studentCode]!.isRevoked) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: attendanceColIdx, rowIndex: rowIdx)).value = TextCellValue(_attendanceMap[studentCode]!.timestamp);
      }
    }

    String outputPath = "${originalFile!.parent.path}/حضور_الطلاب_${DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now())}.xlsx";
    var fileBytes = excel.save();
    if (fileBytes != null) {
      File(outputPath).writeAsBytesSync(fileBytes);
      return outputPath;
    }
    return null;
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<ExamController>(context);

    return Scaffold(
      appBar: AppBar(title: const Text("نظام حضور الامتحانات")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.file_upload),
                label: const Text("استيراد ملف Excel الطلاب"),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                onPressed: () async {
                  FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls']);
                  if (result != null && result.files.single.path != null) {
                    File file = File(result.files.single.path!);
                    var bytes = file.readAsBytesSync();
                    var excel = Excel.decodeBytes(bytes);
                    var sheet = excel.tables[excel.tables.keys.first];
                    if (sheet != null && sheet.rows.length > 1) {
                      List<Student> students = [];
                      for (int i = 1; i < sheet.rows.length; i++) {
                        var r = sheet.rows[i];
                        if (r.isNotEmpty) {
                          students.add(Student(
                            code: r[0]?.value?.toString().trim() ?? '',
                            name: r.length > 1 ? r[1]?.value?.toString().trim() ?? '' : '',
                            grade: r.length > 2 ? r[2]?.value?.toString().trim() ?? '' : '',
                            group: r.length > 3 ? r[3]?.value?.toString().trim() ?? '' : '',
                          ));
                        }
                      }
                      controller.setStudents(students, file, 0);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم استيراد الطلاب بنجاح")));
                    }
                  }
                },
              ),
              const SizedBox(height: 20),
              if (controller.hasData) ...[
                ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text("بدء مسح الحضور (الكاميرا)"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.all(16)),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ScannerScreen()));
                  },
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text("تصدير ملف Excel النهائي"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, padding: const EdgeInsets.all(16)),
                  onPressed: () async {
                    String? path = await controller.exportExcel();
                    if (path != null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تم التصدير بنجاح: $path")));
                    }
                  },
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({Key? key}) : super(key: key);

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _cameraController = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _isProcessing = false;
  Color _overlayColor = Colors.transparent;
  String _statusMessage = "";

  void _onBarcodeDetected(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final String? code = barcodes.first.rawValue;
    if (code == null || code.trim().isEmpty) return;

    setState(() => _isProcessing = true);
    final controller = Provider.of<ExamController>(context, listen: false);
    ScanFeedback feedback = controller.processBarcode(code);

    switch (feedback.type) {
      case ScanResultType.success:
        _overlayColor = Colors.green.withOpacity(0.4);
        _statusMessage = "تم: ${feedback.student?.name}";
        Vibration.vibrate(duration: 80);
        break;
      case ScanResultType.duplicate:
        _overlayColor = Colors.orange.withOpacity(0.5);
        _statusMessage = "${feedback.message}\n${feedback.extraInfo}";
        Vibration.vibrate(pattern: [0, 100, 50, 100]);
        break;
      case ScanResultType.notFound:
        _overlayColor = Colors.red.withOpacity(0.5);
        _statusMessage = "${feedback.message}\n${feedback.extraInfo}";
        Vibration.vibrate(duration: 300);
        break;
    }
    setState(() {});

    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      setState(() {
        _isProcessing = false;
        _overlayColor = Colors.transparent;
        _statusMessage = "";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<ExamController>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("مسح باركود الطلاب"),
        actions: [
          IconButton(icon: const Icon(Icons.flash_on), onPressed: () => _cameraController.toggleTorch()),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                MobileScanner(controller: _cameraController, onDetect: _onBarcodeDetected),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  color: _overlayColor,
                  child: Center(
                    child: _statusMessage.isNotEmpty
                        ? Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                            child: Text(_statusMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[100],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("آخر طالب تم تسجيله:", style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(controller.lastScannedStudent?.name ?? "في انتظار المسح...", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                        if (controller.lastScannedStudent != null) ...[
                          Text("${controller.lastScannedStudent!.grade} — ${controller.lastScannedStudent!.group}"),
                          Text("الوقت: ${controller.lastScanTime}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                        ]
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("إجمالي الحضور:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Chip(label: Text("${controller.totalAttended}", style: const TextStyle(color: Colors.white)), backgroundColor: Colors.blue),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                    icon: const Icon(Icons.undo, color: Colors.white),
                    label: const Text("تراجع عن آخر Scan", style: TextStyle(color: Colors.white)),
                    onPressed: () => controller.undoLastScan(),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
