import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:vibration/vibration.dart';

// رابط Google Apps Script الخاص بك
const String webAppUrl = "https://script.google.com/macros/s/AKfycbyWk-fAbpRNmQs-emoWrtLGuV6gjhcHdqCDEQLgtDhFSBlVyEOITVnIZgoSFedH5VGh/exec";

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AttendanceProvider()..initApp(),
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
  bool isSynced;

  Student({
    required this.code,
    required this.name,
    required this.grade,
    required this.group,
    this.isPresent = false,
    this.attendanceTime,
    this.isSynced = true,
  });

  factory Student.fromJson(Map<String, dynamic> json) {
    return Student(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      grade: json['grade']?.toString() ?? '',
      group: json['group']?.toString() ?? '',
      isPresent: json['isPresent'] == true,
      attendanceTime: json['attendanceTime']?.toString(),
      isSynced: true,
    );
  }
}

class AttendanceProvider extends ChangeNotifier {
  List<Student> _students = [];
  bool _isLoading = false;
  bool _isConnected = true;
  Student? _lastScannedStudent;
  String _searchQuery = '';

  List<Student> get students => _students;
  bool get isLoading => _isLoading;
  bool get isConnected => _isConnected;
  Student? get lastScannedStudent => _lastScannedStudent;

  int get totalCount => _students.length;
  int get presentCount => _students.where((s) => s.isPresent).length;
  int get pendingSyncCount => _students.where((s) => s.isPresent && !s.isSynced).length;

  List<Student> get filteredStudents {
    if (_searchQuery.isEmpty) return _students;
    return _students.where((s) {
      return s.name.contains(_searchQuery) || s.code.contains(_searchQuery);
    }).toList();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void initApp() {
    checkConnectionAndFetch();
  }

  // فحص الاتصال وسحب البيانات من Google Sheets
  Future<void> checkConnectionAndFetch() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.get(Uri.parse(webAppUrl)).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200 || response.statusCode == 302) {
        List<dynamic> jsonList = jsonDecode(response.body);
        _students = jsonList.map((data) => Student.fromJson(data)).toList();
        _isConnected = true;
      } else {
        _isConnected = false;
      }
    } catch (e) {
      _isConnected = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // تسجيل الحضور
  Future<bool> markAttendance(String code) async {
    int index = _students.indexWhere((s) => s.code == code);
    if (index != -1) {
      final student = _students[index];
      _lastScannedStudent = student;

      if (!student.isPresent) {
        String timeStr = DateFormat('hh:mm:ss a').format(DateTime.now());
        student.isPresent = true;
        student.attendanceTime = timeStr;
        student.isSynced = false;
        notifyListeners();

        try {
          Vibration.vibrate(duration: 100);
        } catch (_) {}

        // إرسال التحديث أونلاين
        sendAttendanceToSheet(student);
        return true;
      }
    }
    return false;
  }

  // إرسال بيانات طالب محدد للشيت
  Future<void> sendAttendanceToSheet(Student student) async {
    try {
      final response = await http.post(
        Uri.parse(webAppUrl),
        body: jsonEncode({'code': student.code, 'time': student.attendanceTime}),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        student.isSynced = true;
        _isConnected = true;
        notifyListeners();
      }
    } catch (e) {
      _isConnected = false;
      notifyListeners();
    }
  }

  // مزامنة العناصر غير المنسخة (التي تم حضورها أثناء انقطاع النت)
  Future<void> syncPending() async {
    final pendingList = _students.where((s) => s.isPresent && !s.isSynced).toList();
    for (var student in pendingList) {
      await sendAttendanceToSheet(student);
    }
  }
}

class ExamAttendanceApp extends StatelessWidget {
  const ExamAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'حضور الامتحانات',
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
        useMaterial3: true,
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
        title: const Text('حضور الامتحانات', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => provider.checkConnectionAndFetch(),
            tooltip: 'تحديث البيانات',
          ),
        ],
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // مؤشر حالة الشبكة الجاهزية
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: provider.isConnected ? Colors.green.shade100 : Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: provider.isConnected ? Colors.green : Colors.red),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          provider.isConnected ? Icons.wifi : Icons.wifi_off,
                          color: provider.isConnected ? Colors.green.shade800 : Colors.red.shade800,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          provider.isConnected ? 'جاهز - متصل بالشبكة' : 'غير متصل بالشبكة - تأكد من الإنترنت',
                          style: TextStyle(
                            color: provider.isConnected ? Colors.green.shade900 : Colors.red.shade900,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (provider.pendingSyncCount > 0) ...[
                          const SizedBox(width: 10),
                          InkWell(
                            onTap: () => provider.syncPending(),
                            child: Chip(
                              label: Text('مزامنة المعلق (${provider.pendingSyncCount})', style: const TextStyle(fontSize: 11, color: Colors.white)),
                              backgroundColor: Colors.orange.shade800,
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // بطاقة الإحصائيات
                  Card(
                    color: Colors.indigo.shade50,
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              const Text('إجمالي الطلاب', style: TextStyle(fontSize: 15)),
                              Text('${provider.totalCount}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo)),
                            ],
                          ),
                          Column(
                            children: [
                              const Text('تم حضورهم', style: TextStyle(fontSize: 15)),
                              Text('${provider.presentCount}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // زر فتح شاشة المسح (الكاميرا)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ScannerScreen()),
                      );
                    },
                    icon: const Icon(Icons.camera_alt, size: 26),
                    label: const Text('فتح كاميرا المسح والتحضير', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),

                  // شريط البحث اليدوي
                  TextField(
                    onChanged: (val) => provider.setSearchQuery(val),
                    decoration: InputDecoration(
                      hintText: 'ابحث عن طالب بالاسم أو الكود...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // قائمة الطلاب
                  Expanded(
                    child: ListView.builder(
                      itemCount: provider.filteredStudents.length,
                      itemBuilder: (context, index) {
                        final student = provider.filteredStudents[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: student.isPresent ? Colors.green : Colors.grey.shade300,
                              child: Icon(
                                student.isPresent ? Icons.check : Icons.person,
                                color: student.isPresent ? Colors.white : Colors.grey.shade700,
                              ),
                            ),
                            title: Text(student.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('كود: ${student.code} | ${student.grade} - ${student.group}'),
                            trailing: student.isPresent
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(student.attendanceTime ?? 'حاضر', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                      const SizedBox(width: 4),
                                      Icon(
                                        student.isSynced ? Icons.cloud_done : Icons.cloud_upload,
                                        size: 18,
                                        color: student.isSynced ? Colors.green : Colors.orange,
                                      )
                                    ],
                                  )
                                : ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.indigo,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                    ),
                                    onPressed: () {
                                      provider.markAttendance(student.code);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('تم تحضير الطالب: ${student.name}'), backgroundColor: Colors.green),
                                      );
                                    },
                                    child: const Text('تحضير يدوياً'),
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

// شاشة المسح المقسمة
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AttendanceProvider>(context);
    final lastStudent = provider.lastScannedStudent;

    return Scaffold(
      appBar: AppBar(title: const Text('مسح الباركود')),
      body: Column(
        children: [
          // الجزء العلوي: نافذة الكاميرا
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.42,
            child: MobileScanner(
              onDetect: (capture) {
                if (_isProcessing) return;

                final List<Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  final String? rawCode = barcode.rawValue;
                  if (rawCode != null && rawCode.isNotEmpty) {
                    setState(() => _isProcessing = true);

                    provider.markAttendance(rawCode.trim());

                    Future.delayed(const Duration(milliseconds: 1200), () {
                      if (mounted) {
                        setState(() => _isProcessing = false);
                      }
                    });
                    break;
                  }
                }
              },
            ),
          ),

          // الجزء السفلي: البيانات الممسوحة ومؤشر الشبكة
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey.shade100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (lastStudent != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: lastStudent.isPresent ? Colors.green.shade50 : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: lastStudent.isPresent ? Colors.green : Colors.grey.shade300, width: 2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                lastStudent.isPresent ? Icons.check_circle : Icons.info,
                                color: lastStudent.isPresent ? Colors.green : Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  lastStudent.name,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Text(
                                lastStudent.attendanceTime ?? '',
                                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const Divider(),
                          Text('الكود: ${lastStudent.code}  |  الصف: ${lastStudent.grade}  |  المجموعة: ${lastStudent.group}'),
                        ],
                      ),
                    ),
                  ] else ...[
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Text('قم بتوجيه الكاميرا نحو الباركود للبدء', style: TextStyle(color: Colors.grey, fontSize: 16)),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text('إجمالي الحضور: ${provider.presentCount} / ${provider.totalCount}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('إغلاق الكاميرا'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
