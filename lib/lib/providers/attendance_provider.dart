import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/student.dart';
import '../services/storage_service.dart';

class AttendanceProvider extends ChangeNotifier {
  AttendanceProvider({required StorageService storageService})
      : _storage = storageService;

  final StorageService _storage;

  String _webAppUrl = '';
  List<Student> _students = [];
  bool _isLoading = false;
  bool _isConnected = true;
  String _searchQuery = '';

  List<Student> get students => _students;
  bool get isLoading => _isLoading;
  bool get isConnected => _isConnected;
  int get totalCount => _students.length;
  int get presentCount => _students.where((s) => s.isPresent).length;
  int get pendingSyncCount =>
      _students.where((s) => s.isPresent && !s.isSynced).length;

  List<Student> get filteredStudents {
    if (_searchQuery.isEmpty) return _students.where((s) => s.isPresent).toList();
    final q = _searchQuery.trim().toLowerCase();
    return _students.where((s) {
      return s.name.toLowerCase().contains(q) || s.code.toLowerCase().contains(q);
    }).toList();
  }

  /// يُستدعى من ChangeNotifierProxyProvider كلما تغيّر رابط الـ WebApp في الإعدادات.
  void updateWebAppUrl(String url) {
    _webAppUrl = url;
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
    final localList = _storage.loadAll();
    for (final localStudent in localList) {
      final index = _students.indexWhere((s) => s.code == localStudent.code);
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
    notifyListeners();
  }

  Future<void> fetchStudentsFromSheet() async {
    if (_webAppUrl.trim().isEmpty || _webAppUrl.contains('REPLACE_WITH_YOUR')) {
      _isConnected = false;
      notifyListeners();
      return;
    }
    try {
      final response =
          await http.get(Uri.parse(_webAppUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        final Map<String, Student> currentMap = {for (var s in _students) s.code: s};

        final List<Student> newStudents = data.map((item) {
          final String code = item['code'].toString();
          if (currentMap.containsKey(code) && currentMap[code]!.isPresent) {
            return currentMap[code]!;
          }
          return Student(
            code: code,
            name: item['name']?.toString() ?? '',
            grade: item['grade']?.toString() ?? '',
            timeGroup: item['timeGroup']?.toString() ?? '',
            isPresent: item['isPresent'] == true,
            attendanceTime: item['attendanceTime']?.toString() ?? '',
            isSynced: item['isPresent'] == true,
          );
        }).toList();

        _students = newStudents;
        _isConnected = true;
        await _storage.saveAll(_students);
        await _storage.pruneMissing(_students.map((s) => s.code).toSet());
      } else {
        _isConnected = false;
      }
    } catch (e) {
      _isConnected = false;
    }
    notifyListeners();
  }

  Future<String> markAttendance(String code) async {
    final index = _students.indexWhere((s) => s.code.trim() == code.trim());
    if (index == -1) {
      await _playFeedback(success: false);
      return "كود غير موجود!";
    }

    final student = _students[index];
    if (student.isPresent) {
      await _playFeedback(success: false);
      return "تم تحضير الطالب سابقاً!";
    }

    student.isPresent = true;
    student.attendanceTime = DateFormat('hh:mm:ss a').format(DateTime.now());
    student.isSynced = false;

    notifyListeners();
    await _storage.saveStudent(student);
    await _playFeedback(success: true);

    // مزامنة في الخلفية دون انتظار المستخدم
    unawaited(sendAttendanceToSheet(student));
    return "SUCCESS:${student.name}";
  }

  Future<void> _playFeedback({required bool success}) async {
    try {
      await SystemSound.play(success ? SystemSoundType.click : SystemSoundType.alert);
    } catch (_) {
      // بعض الأجهزة/المنصات لا تدعم الصوت النظامي - تجاهل بأمان
    }
  }

  Future<void> sendAttendanceToSheet(Student student) async {
    if (_webAppUrl.trim().isEmpty || _webAppUrl.contains('REPLACE_WITH_YOUR')) {
      _isConnected = false;
      notifyListeners();
      return;
    }
    try {
      final client = http.Client();
      final request = http.Request('POST', Uri.parse(_webAppUrl))
        ..followRedirects = true
        ..maxRedirects = 5
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({'code': student.code, 'time': student.attendanceTime});

      final streamedResponse =
          await client.send(request).timeout(const Duration(seconds: 8));
      final response = await http.Response.fromStream(streamedResponse);
      client.close();

      if (response.statusCode == 200 || response.statusCode == 302) {
        student.isSynced = true;
        _isConnected = true;
      } else {
        _isConnected = false;
      }
    } catch (e) {
      _isConnected = false;
    }
    await _storage.saveStudent(student);
    notifyListeners();
  }

  Future<void> syncPending() async {
    final pendingList = _students.where((s) => s.isPresent && !s.isSynced).toList();
    for (final student in pendingList) {
      await sendAttendanceToSheet(student);
    }
  }
}

// مساعد بسيط بدل الاعتماد على package:pedantic
void unawaited(Future<void> future) {}
