import 'dart:convert';

class UserModel {
  final String userName;
  final String employeeId;
  final String email;
  final String role;
  final String designation;
  final String? department;
  final String? createdAt;
  final String? lastSignInAt;
  final String? profilePicUrl;

  UserModel({
    required this.userName,
    required this.employeeId,
    required this.email,
    required this.role,
    required this.designation,
    this.department,
    this.createdAt,
    this.lastSignInAt,
    this.profilePicUrl,
  });

  // Factory constructor to create a UserModel from a map (JSON)
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      userName: json['user_name'] ?? json['userName'] ?? json['name'] ?? '',
      employeeId: json['employee_id'] ?? json['employeeId'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? '',
      designation: json['designation'] ?? '',
      department: json['department'],
      createdAt: json['created_at'] ?? json['createdAt'],
      lastSignInAt: json['last_sign_in_at'] ?? json['lastSignInAt'],
      profilePicUrl:
          json['profile_pic_url'] ??
          json['profilePicUrl'] ??
          json['photoURL'], // Common variations
    );
  }

  // Method to convert UserModel to a map (JSON)
  Map<String, dynamic> toJson() {
    return {
      'user_name': userName,
      'employee_id': employeeId,
      'email': email,
      'role': role,
      'designation': designation,
      'department': department,
      'created_at': createdAt,
      'last_sign_in_at': lastSignInAt,
      'profile_pic_url': profilePicUrl,
    };
  }

  // Helper to encode to JSON string for storage
  String toRawJson() => json.encode(toJson());

  // Helper to decode from JSON string from storage
  factory UserModel.fromRawJson(String str) =>
      UserModel.fromJson(json.decode(str));

  @override
  String toString() {
    return 'UserModel(userName: $userName, employeeId: $employeeId, role: $role)';
  }
}
