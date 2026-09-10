class StudentProfile {
  final int studentId;
  final String studentNumber;

  final String firstName;
  final String middleName;
  final String surname;
  final String extension;

  final String email;

  final String degree;
  final String yearSection;
  final String semester;
  final String academicYear;

  final String verificationStatus;

  const StudentProfile({
    required this.studentId,
    required this.studentNumber,
    required this.firstName,
    required this.middleName,
    required this.surname,
    required this.extension,
    required this.email,
    required this.degree,
    required this.yearSection,
    required this.semester,
    required this.academicYear,
    required this.verificationStatus,
  });

  factory StudentProfile.fromJson(
    Map<String, dynamic> json,
  ) {
    final user = _mapValue(
      json['user'],
    );

    final student = _mapValue(
      json['student'],
    );

    // Some /me implementations return the user/student
    // directly inside data rather than under user/student.
    final source = student.isNotEmpty
        ? student
        : user.isNotEmpty
            ? user
            : json;

    return StudentProfile(
      studentId: _intValue(
        source['student_id'] ??
            user['student_id'] ??
            json['student_id'],
      ),
      studentNumber: _stringValue(
        source['student_number'] ??
            user['student_number'] ??
            json['student_number'],
      ),
      firstName: _stringValue(
        source['firstname'] ??
            source['first_name'] ??
            user['firstname'] ??
            user['first_name'] ??
            json['firstname'] ??
            json['first_name'],
      ),
      middleName: _stringValue(
        source['middlename'] ??
            source['middle_name'] ??
            user['middlename'] ??
            user['middle_name'] ??
            json['middlename'] ??
            json['middle_name'],
      ),
      surname: _stringValue(
        source['surname'] ??
            source['last_name'] ??
            user['surname'] ??
            user['last_name'] ??
            json['surname'] ??
            json['last_name'],
      ),
      extension: _stringValue(
        source['ext'] ??
            source['extension'] ??
            user['ext'] ??
            user['extension'] ??
            json['ext'] ??
            json['extension'],
      ),
      email: _stringValue(
        source['email'] ??
            user['email'] ??
            json['email'],
      ),
      degree: _stringValue(
        source['degree'] ??
            user['degree'] ??
            json['degree'],
      ),
      yearSection: _stringValue(
        source['year_section'] ??
            source['year_and_section'] ??
            user['year_section'] ??
            user['year_and_section'] ??
            json['year_section'] ??
            json['year_and_section'],
      ),
      semester: _stringValue(
        source['semester'] ??
            user['semester'] ??
            json['semester'],
      ),
      academicYear: _stringValue(
        source['academic_year'] ??
            user['academic_year'] ??
            json['academic_year'],
      ),
      verificationStatus: _stringValue(
        user['verification_status'] ??
            source['verification_status'] ??
            json['verification_status'],
      ),
    );
  }

  String get fullName {
    final parts = <String>[
      firstName,
      middleName,
      surname,
      extension,
    ].where(
      (value) => value.trim().isNotEmpty,
    );

    return parts.join(' ');
  }

  String get displayName {
    if (fullName.isNotEmpty) {
      return fullName;
    }

    if (studentNumber.isNotEmpty) {
      return studentNumber;
    }

    return 'Student';
  }

  bool get isVerified {
    final value =
        verificationStatus.trim().toLowerCase();

    return value == 'verified' ||
        value == 'complete' ||
        value == 'completed';
  }

  static Map<String, dynamic> _mapValue(
    dynamic value,
  ) {
    if (value is Map) {
      return Map<String, dynamic>.from(
        value,
      );
    }

    return <String, dynamic>{};
  }

  static int _intValue(
    dynamic value,
  ) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  static String _stringValue(
    dynamic value,
  ) {
    if (value == null) {
      return '';
    }

    final text =
        value.toString().trim();

    if (text.isEmpty ||
        text.toLowerCase() == 'null') {
      return '';
    }

    return text;
  }
}