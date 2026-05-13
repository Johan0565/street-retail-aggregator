import 'dart:convert';

class SavedAccount {
  final String email;
  final String role;
  final String token;
  final String? displayName;
  final DateTime lastUsedAt;

  SavedAccount({
    required this.email,
    required this.role,
    required this.token,
    this.displayName,
    required this.lastUsedAt,
  });

  SavedAccount copyWith({
    String? email,
    String? role,
    String? token,
    String? displayName,
    DateTime? lastUsedAt,
  }) {
    return SavedAccount(
      email: email ?? this.email,
      role: role ?? this.role,
      token: token ?? this.token,
      displayName: displayName ?? this.displayName,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  String get initials {
    final source = (displayName != null && displayName!.trim().isNotEmpty)
        ? displayName!.trim()
        : email;
    final clean = source.replaceAll(RegExp(r'[^A-Za-zА-Яа-яЁё0-9]+'), ' ').trim();
    if (clean.isEmpty) return '?';
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  Map<String, dynamic> toJson() => {
        'email': email,
        'role': role,
        'token': token,
        'displayName': displayName,
        'lastUsedAt': lastUsedAt.toIso8601String(),
      };

  factory SavedAccount.fromJson(Map<String, dynamic> json) => SavedAccount(
        email: json['email'] as String,
        role: json['role'] as String,
        token: json['token'] as String,
        displayName: json['displayName'] as String?,
        lastUsedAt: DateTime.tryParse(json['lastUsedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  static List<SavedAccount> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(SavedAccount.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String encodeList(List<SavedAccount> accounts) =>
      jsonEncode(accounts.map((a) => a.toJson()).toList());
}
