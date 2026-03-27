import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  const UserModel({
    required this.uid,
    required this.email,
    required this.name,
    required this.age,
    required this.pregnancyWeeks,
    required this.bloodGroup,
    required this.hemoglobin,
    required this.wbc,
    required this.bloodPressure,
    required this.sugarLevel,
    required this.weight,
    required this.symptoms,
    required this.medicalHistory,
    this.updatedAt,
  });

  final String uid;
  final String email;
  final String name;
  final int age;
  final int pregnancyWeeks;
  final String bloodGroup;
  final double hemoglobin;
  final double wbc;
  final String bloodPressure;
  final double sugarLevel;
  final double weight;
  final String symptoms;
  final String medicalHistory;
  final DateTime? updatedAt;

  bool get isComplete =>
      name.trim().isNotEmpty &&
      age > 0 &&
      pregnancyWeeks >= 0 &&
      bloodGroup.trim().isNotEmpty &&
      hemoglobin > 0 &&
      wbc > 0 &&
      bloodPressure.trim().isNotEmpty &&
      sugarLevel > 0 &&
      weight > 0;

  factory UserModel.empty({required String uid, required String email}) {
    return UserModel(
      uid: uid,
      email: email,
      name: '',
      age: 0,
      pregnancyWeeks: 0,
      bloodGroup: '',
      hemoglobin: 0,
      wbc: 0,
      bloodPressure: '',
      sugarLevel: 0,
      weight: 0,
      symptoms: '',
      medicalHistory: '',
    );
  }

  factory UserModel.fromMap(Map<String, dynamic> data) {
    final updatedAtRaw = data['updatedAt'];
    return UserModel(
      uid: data['uid'] as String? ?? '',
      email: data['email'] as String? ?? '',
      name: data['name'] as String? ?? '',
      age: (data['age'] as num?)?.toInt() ?? 0,
      pregnancyWeeks: (data['pregnancyWeeks'] as num?)?.toInt() ?? 0,
      bloodGroup: data['bloodGroup'] as String? ?? '',
      hemoglobin: (data['hemoglobin'] as num?)?.toDouble() ?? 0,
      wbc: (data['wbc'] as num?)?.toDouble() ?? 0,
      bloodPressure: data['bloodPressure'] as String? ?? '',
      sugarLevel: (data['sugarLevel'] as num?)?.toDouble() ?? 0,
      weight: (data['weight'] as num?)?.toDouble() ?? 0,
      symptoms: data['symptoms'] as String? ?? '',
      medicalHistory: data['medicalHistory'] as String? ?? '',
      updatedAt: updatedAtRaw is Timestamp
          ? updatedAtRaw.toDate()
          : updatedAtRaw is DateTime
          ? updatedAtRaw
          : null,
    );
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? name,
    int? age,
    int? pregnancyWeeks,
    String? bloodGroup,
    double? hemoglobin,
    double? wbc,
    String? bloodPressure,
    double? sugarLevel,
    double? weight,
    String? symptoms,
    String? medicalHistory,
    DateTime? updatedAt,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      name: name ?? this.name,
      age: age ?? this.age,
      pregnancyWeeks: pregnancyWeeks ?? this.pregnancyWeeks,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      hemoglobin: hemoglobin ?? this.hemoglobin,
      wbc: wbc ?? this.wbc,
      bloodPressure: bloodPressure ?? this.bloodPressure,
      sugarLevel: sugarLevel ?? this.sugarLevel,
      weight: weight ?? this.weight,
      symptoms: symptoms ?? this.symptoms,
      medicalHistory: medicalHistory ?? this.medicalHistory,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'uid': uid,
      'email': email,
      'name': name.trim(),
      'age': age,
      'pregnancyWeeks': pregnancyWeeks,
      'bloodGroup': bloodGroup.trim(),
      'hemoglobin': hemoglobin,
      'wbc': wbc,
      'bloodPressure': bloodPressure.trim(),
      'sugarLevel': sugarLevel,
      'weight': weight,
      'symptoms': symptoms.trim(),
      'medicalHistory': medicalHistory.trim(),
      'updatedAt': updatedAt ?? DateTime.now().toUtc(),
    };
  }

  String toAiSummary() {
    return 'Name: $name\n'
        'Age: $age\n'
        'Pregnancy weeks: $pregnancyWeeks\n'
        'Blood group: $bloodGroup\n'
        'Hemoglobin: ${hemoglobin.toStringAsFixed(1)} g/dL\n'
        'WBC: ${wbc.toStringAsFixed(1)}\n'
        'Blood pressure: $bloodPressure\n'
        'Sugar level: ${sugarLevel.toStringAsFixed(1)} mg/dL\n'
        'Weight: ${weight.toStringAsFixed(1)} kg\n'
        'Symptoms: ${symptoms.isEmpty ? 'None reported' : symptoms}\n'
        'Medical history: ${medicalHistory.isEmpty ? 'None reported' : medicalHistory}';
  }
}
