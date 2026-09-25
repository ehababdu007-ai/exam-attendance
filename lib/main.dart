import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:vibration/vibration.dart';
import 'package:provider/provider.dart';

const String webAppUrl = "https://script.google.com/macros/s/AKfycbyYt6jFj5M-8B9M_J-_GqT-uJ3J_u00/exec";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AttendanceProvider()..loadInitialData(),
      child: const ExamAttendanceApp(),
    ),
  );
}

class Student {
  final String code;
  final String name;
  final String grade;
  final String timeGroup;
  bool isPresent;
  String attendanceTime;
  bool isSynced;

  Student({
    required this.code,
    required this.name,
    required this.grade,
    required this.timeGroup,
    this.isPresent = false,
    this.attendanceTime = '',
    this.isSynced = false,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'grade': grade,
        'timeGroup': timeGroup,
        'isPresent': isPresent,
        'attendanceTime': attendanceTime,
        'isSynced': isSynced,
      };

  factory Student.fromJson(Map<String, dynamic> json) => Student(
        code: json['code'].toString(),
        name: json['name'] ?? '',
        grade: json['grade'] ?? '',
        timeGroup: json['timeGroup'] ?? '',
        isPresent: json['isPresent'] ?? false,
        attendanceTime: json['attendanceTime'] ?? '',
        isSynced: json['isSynced'] ?? false,
      );
}

class AttendanceProvider extends ChangeNotifier {
  List<Student> _students = [];
  bool _isLoading = false;
  bool _isConnected = true;
  String _searchQuery = '';

  List<Student> get students => _students;
  bool get isLoading => _isLoading;
  bool get isConnected => _isConnected;
  int get totalCount => _students.length;
  int get presentCount => _students.where((s) => s.isPresent).toList().length;
  int get pendingSyncCount => _students.where((s) => s.isPresent && !s.isSynced).toList().length;

  List<Student> get filteredStudents {
    if (_searchQuery.isEmpty) return _students.where((s) => s.isPresent).toList();
    return _students.where((s) {
      final q = _searchQuery.trim().toLowerCase();
      return s.name.toLowerCase().contains(q) || s.code.toLowerCase().contains(q);
    }).toList();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> loadInitialData() async {
    _isLoading = true;
    notifyListeners();
    
    await recoverLocalData();
    await fetchStudentsFromSheet();
    
    _isLoading = false;
    notifyListeners();
  }

  Future<void> recoverLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cachedData = prefs.getString('cached_students');

    if (cachedData != null) {
      try {
        List<dynamic> decoded = jsonDecode(cachedData);
        List<Student> localList = decoded.map((item) => Student.fromJson(item)).toList();
        
        for (var localStudent in localList) {
          int index = _students.indexWhere((s) => s.code == localStudent.code);
          if (index != -1) {
            if (localStudent.isPresent) {
              _students[index].isPresent = true;
              _students[index].attendanceTime = localStudent.attendanceTime;
              _students[index].isSynced = localStudent.isSynced;
            }
          } else {
            _students.add(localStudent);
          }
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> fetchStudentsFromSheet() async {
    try {
      final response = await http.get(Uri.parse(webAppUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        List<dynamic> data = jsonDecode(response.body);
        
        Map<String, Student> currentMap = {for (var s in _students) s.code: s};

        List<Student> newStudents = data.map((item) {
          String code = item['code'].toString();
          if (currentMap.containsKey(code) && currentMap[code]!.isPresent) {
            return currentMap[code]!;
          }
          return Student(
            code: code,
            name: item['name'] ?? '',
            grade: item['grade'] ?? '',
            timeGroup: item['timeGroup'] ?? '',
            isPresent: item['isPresent'] ?? false,
            attendanceTime: item['attendanceTime'] ?? '',
            isSynced: item['isPresent'] ?? false,
          );
        }).toList();

        _students = newStudents;
        _isConnected = true;
        await _saveToCache();
      }
    } catch (e) {
      _isConnected = false;
    }
    notifyListeners();
  }

  Future<void> _saveToCache() async {
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> data = _students.map((s) => s.toJson()).toList();
    await prefs.setString('cached_students', jsonEncode(data));
  }

  Future<String> markAttendance(String code) async {
    final index = _students.indexWhere((s) => s.code.trim() == code.trim());
    if (index == -1) return "كود غير موجود!";

    final student = _students[index];
    if (student.isPresent) return "تم تحضير الطالب سابقاً!";

    student.isPresent = true;
    student.attendanceTime = DateFormat('hh:mm:ss a').format(DateTime.now());
    student.isSynced = false;

    notifyListeners();
    await _saveToCache();

    sendAttendanceToSheet(student);
    return "SUCCESS:${student.name}";
  }

  Future<void> sendAttendanceToSheet(Student student) async {
    try {
      final client = http.Client();
      final request = http.Request('POST', Uri.parse(webAppUrl))
        ..followRedirects = true
        ..maxRedirects = 5
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({'code': student.code, 'time': student.attendanceTime});

      final streamedResponse = await client.send(request).timeout(const Duration(seconds: 8));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 302) {
        student.isSynced = true;
        _isConnected = true;
      } else {
        _isConnected = false;
      }
    } catch (e) {
      _isConnected = false;
    }
    await _saveToCache();
    notifyListeners();
  }

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
        fontFamily: 'Cairo',
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
            icon: const Icon(Icons.restore),
            tooltip: 'استرجاع الحضور المحلي',
            onPressed: () async {
              await provider.recoverLocalData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم استرجاع سجلات الحضور المحفوظة على الموبايل ✅')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث البيانات من الشيت',
            onPressed: () => provider.fetchStudentsFromSheet(),
          )
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
                                : 'جاري الاتصال بالسيرفر...',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => provider.syncPending(),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800),
                          child: const Text('مزامنة الآن', style: TextStyle(color: Colors.white)),
                        )
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Card(
                          color: Colors.blue.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                const Text('إجمالي الطلاب', style: TextStyle(fontSize: 16)),
                                Text('${provider.totalCount}',
                                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Card(
                          color: Colors.green.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                const Text('تم حضورهم', style: TextStyle(fontSize: 16)),
                                Text('${provider.presentCount}',
                                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.horizontal(12.0),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScannerScreen())),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('فتح كاميرا المسح والتحضير', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
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
                                  backgroundColor: student.isSynced ? Colors.green : Colors.amber,
                                  child: Icon(student.isSynced ? Icons.check : Icons.cloud_upload, color: Colors.white),
                                ),
                                title: Text(student.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('كود: ${student.code} | ${student.grade} - ${student.timeGroup}'),
                                trailing: Text(
                                  student.attendanceTime,
                                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
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

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class ScannerScreenState extends State<ScannerScreen> {
  bool isProcessing = false;

  void _onDetect(BarcodeCapture capture, AttendanceProvider provider) async {
    if (isProcessing) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? rawCode = barcodes.first.rawValue;
    if (rawCode == null || rawCode.isEmpty) return;

    setState(() => isProcessing = true);

    try {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 100);
      }
    } catch (_) {}

    String result = await provider.markAttendance(rawCode);

    if (!mounted) return;

    if (result.startsWith("SUCCESS:")) {
      String name = result.split(":")[1];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تحضير: $name بنجاح ✅', style: const TextStyle(fontSize: 16)),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result, style: const TextStyle(fontSize: 16)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => isProcessing = false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AttendanceProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(title: const Text('مسح الباركود')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) => _onDetect(capture, provider),
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
