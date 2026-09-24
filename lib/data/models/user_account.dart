/// صارف اکاؤنٹ ماڈل
/// UserAccount — a system user managed by the admin
/// Stored in public.user_accounts (separate from auth.users)

class UserAccount {
  final String? id;
  final String name;
  final String email;
  final String roleName;      // key matching AppRole.name
  final String roleNameUrdu;  // display label
  final String? linkedStaffId;   // optional FK to public.staff
  final String? linkedParentId;  // optional FK to public.parents
  final bool isActive;

  /// Transient — only used when creating a new account. Never stored/serialized.
  final String? password;

  const UserAccount({
    this.id,
    required this.name,
    required this.email,
    required this.roleName,
    required this.roleNameUrdu,
    this.linkedStaffId,
    this.linkedParentId,
    this.isActive = true,
    this.password,
  });

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
      id:             json['id'] as String?,
      name:           json['name'] as String,
      email:          json['email'] as String,
      roleName:       json['role_name'] as String? ?? 'teacher',
      roleNameUrdu:   json['role_name_urdu'] as String? ?? 'استاد',
      linkedStaffId:  json['linked_staff_id'] as String?,
      linkedParentId: json['linked_parent_id'] as String?,
      isActive:       json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'name':             name,
    'email':            email,
    'role_name':        roleName,
    'role_name_urdu':   roleNameUrdu,
    'linked_staff_id':  linkedStaffId,
    'linked_parent_id': linkedParentId,
    'is_active':        isActive,
  };

  /// First letter(s) of name for avatar fallback.
  String get initials {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) return '${words[0][0]}${words[1][0]}';
    return name.isNotEmpty ? name[0] : '?';
  }

  UserAccount copyWith({bool? isActive, String? roleNameUrdu, String? roleName}) {
    return UserAccount(
      id:             id,
      name:           name,
      email:          email,
      // password intentionally not copied — it's only for initial creation
      roleName:       roleName      ?? this.roleName,
      roleNameUrdu:   roleNameUrdu  ?? this.roleNameUrdu,
      linkedStaffId:  linkedStaffId,
      linkedParentId: linkedParentId,
      isActive:       isActive      ?? this.isActive,
    );
  }
}
