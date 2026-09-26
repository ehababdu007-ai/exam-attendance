import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../models/student.dart';

class ExportService {
  /// يبني ملف CSV لطلاب الحضور فقط، ويفتح شاشة المشاركة (واتساب / حفظ محلي).
  static Future<void> exportPresentStudents(List<Student> allStudents) async {
    final present = allStudents.where((s) => s.isPresent).toList();

    final List<List<dynamic>> rows = [
      ['الكود', 'الاسم', 'الصف', 'المجموعة', 'وقت الحضور', 'تمت المزامنة'],
      ...present.map((s) => [
            s.code,
            s.name,
            s.grade,
            s.timeGroup,
            s.attendanceTime,
            s.isSynced ? 'نعم' : 'لا',
          ]),
    ];

    final String csvData = const ListToCsvConverter().convert(rows);
    // BOM حتى يفتح إكسل الملف بترميز عربي صحيح
    final String csvWithBom = '\uFEFF$csvData';

    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final file = File('${dir.path}/attendance_$stamp.csv');
    await file.writeAsString(csvWithBom, encoding: utf8);

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'تقرير الحضور - $stamp'),
    );
  }
}
