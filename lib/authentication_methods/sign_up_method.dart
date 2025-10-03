class SignUpMethod {
  final String firstName;
  final String lastName;
  final String phoneNumber; // unique
  final String username; // unique (case-insensitive via UsernameLower)
  final String email; // unique
  final String password; // DO NOT store to DB
  final String? gender; // optional
  final DateTime? dateOfBirth; // optional

  // Generated
  final String userId; // Firebase UID
  final int customerId; // starts at 20259 and increments
  final String serialNumber; // unique

  SignUpMethod({
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    required this.username,
    required this.email,
    required this.password,
    required this.userId,
    required this.customerId,
    required this.serialNumber,
    this.gender,
    this.dateOfBirth,
  });

  Map<String, dynamic> toJson() {
    return {
      'FirstName': firstName,
      'LastName': lastName,
      'PhoneNumber': phoneNumber,
      'Username': username,
      'UsernameLower': username.toLowerCase(),
      'Email': email,
      'Gender': gender,
      if (dateOfBirth != null) 'DateOfBirth': dateOfBirth!.toIso8601String(),
      // generated/meta fields
      'UserId': userId,
      'CustomerId': customerId, // e.g. 20259
      'SerialNumber': serialNumber, // e.g. SN-20250301153012-4821
      'CreatedAt': DateTime.now().toIso8601String(),
      'EmailVerified': false,
    };
  }
}
