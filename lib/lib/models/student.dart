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

  factory Student.fromJson(Map<dynamic, dynamic> json) => Student(
        code: json['code'].toString(),
        name: json['name']?.toString() ?? '',
        grade: json['grade']?.toString() ?? '',
        timeGroup: json['timeGroup']?.toString() ?? '',
        isPresent: json['isPresent'] == true,
        attendanceTime: json['attendanceTime']?.toString() ?? '',
        isSynced: json['isSynced'] == true,
      );

  Student copy() => Student(
        code: code,
        name: name,
        grade: grade,
        timeGroup: timeGroup,
        isPresent: isPresent,
        attendanceTime: attendanceTime,
        isSynced: isSynced,
      );
}
