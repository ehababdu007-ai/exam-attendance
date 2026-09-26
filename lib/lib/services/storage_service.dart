import 'package:hive_flutter/hive_flutter.dart';
import '../models/student.dart';

/// طبقة تخزين محلي مبنية على Hive (بديل SharedPreferences).
///
/// السبب في الترقية: Hive يخزن كل طالب في سجل مستقل داخل الـ Box،
/// بدلاً من نص JSON واحد ضخم في SharedPreferences، وبالتالي:
/// - تحديث طالب واحد لا يعيد كتابة كل البيانات (أداء وأمان أفضل).
/// - أقل عرضة للتلف أو الفقد الكامل عند مسح الكاش من النظام.
class StorageService {
  static const String _boxName = 'students_box';
  Box<dynamic>? _box;

  Future<void> init() async {
    _box = await Hive.openBox<dynamic>(_boxName);
  }

  Box<dynamic> get _safeBox {
    final box = _box;
    if (box == null) {
      throw StateError('StorageService لم يتم تهيئته. نادِ init() أولاً.');
    }
    return box;
  }

  List<Student> loadAll() {
    return _safeBox.values
        .map((e) => Student.fromJson(Map<dynamic, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveStudent(Student student) async {
    await _safeBox.put(student.code, student.toJson());
  }

  Future<void> saveAll(List<Student> students) async {
    final Map<String, Map<String, dynamic>> entries = {
      for (final s in students) s.code: s.toJson(),
    };
    await _safeBox.putAll(entries);
  }

  /// يحذف من التخزين المحلي أي طالب غير موجود في القائمة الجديدة القادمة
  /// من الشيت (مع الحفاظ دائماً على الطلاب الحاضرين محلياً حتى لو حُذفوا
  /// من الشيت، حتى لا يضيع تحضير تم تسجيله بالفعل).
  Future<void> pruneMissing(Set<String> validCodes) async {
    final keysToRemove = _safeBox.keys.where((k) {
      if (validCodes.contains(k)) return false;
      final raw = _safeBox.get(k);
      if (raw is Map && raw['isPresent'] == true) return false;
      return true;
    }).toList();
    if (keysToRemove.isNotEmpty) {
      await _safeBox.deleteAll(keysToRemove);
    }
  }

  Future<void> clear() async {
    await _safeBox.clear();
  }
}
