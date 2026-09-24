/// مدرسہ ماڈل
/// Madrasa — one institution in the franchise network

class Madrasa {
  final String? id;
  final String nameUrdu;
  final String nameEnglish;
  final String cityUrdu;
  final String cityEnglish;
  final String? address;
  final String? phone;
  final String? email;
  final String? website;
  final String? logoUrl;
  final String? branchCode;
  final String? adminUserId;   // FK → auth.users (the assigned madrasa admin)
  final String subscriptionPlan; // 'basic' | 'standard' | 'premium'
  final bool isActive;
  final DateTime? createdAt;

  const Madrasa({
    this.id,
    required this.nameUrdu,
    required this.nameEnglish,
    required this.cityUrdu,
    required this.cityEnglish,
    this.address,
    this.phone,
    this.email,
    this.website,
    this.logoUrl,
    this.branchCode,
    this.adminUserId,
    this.subscriptionPlan = 'basic',
    this.isActive = true,
    this.createdAt,
  });

  factory Madrasa.fromJson(Map<String, dynamic> j) => Madrasa(
        id:               j['id'] as String?,
        nameUrdu:         j['name_urdu'] as String? ?? '',
        nameEnglish:      j['name_english'] as String? ?? '',
        cityUrdu:         j['city_urdu'] as String? ?? '',
        cityEnglish:      j['city_english'] as String? ?? '',
        address:          j['address'] as String?,
        phone:            j['phone'] as String?,
        email:            j['email'] as String?,
        website:          j['website'] as String?,
        logoUrl:          j['logo_url'] as String?,
        branchCode:       j['branch_code'] as String?,
        adminUserId:      j['admin_user_id'] as String?,
        subscriptionPlan: j['subscription_plan'] as String? ?? 'basic',
        isActive:         j['is_active'] as bool? ?? true,
        createdAt:        j['created_at'] != null
            ? DateTime.tryParse(j['created_at'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'name_urdu':          nameUrdu,
        'name_english':       nameEnglish,
        'city_urdu':          cityUrdu,
        'city_english':       cityEnglish,
        'address':            address,
        'phone':              phone,
        'email':              email,
        'website':            website,
        'logo_url':           logoUrl,
        'branch_code':        branchCode,
        'admin_user_id':      adminUserId,
        'subscription_plan':  subscriptionPlan,
        'is_active':          isActive,
      };

  Madrasa copyWith({
    String? nameUrdu, String? nameEnglish,
    String? cityUrdu, String? cityEnglish,
    String? address, String? phone, String? email,
    String? website, String? logoUrl, String? branchCode,
    String? adminUserId, String? subscriptionPlan, bool? isActive,
  }) => Madrasa(
    id: id, createdAt: createdAt,
    nameUrdu:         nameUrdu         ?? this.nameUrdu,
    nameEnglish:      nameEnglish      ?? this.nameEnglish,
    cityUrdu:         cityUrdu         ?? this.cityUrdu,
    cityEnglish:      cityEnglish      ?? this.cityEnglish,
    address:          address          ?? this.address,
    phone:            phone            ?? this.phone,
    email:            email            ?? this.email,
    website:          website          ?? this.website,
    logoUrl:          logoUrl          ?? this.logoUrl,
    branchCode:       branchCode       ?? this.branchCode,
    adminUserId:      adminUserId      ?? this.adminUserId,
    subscriptionPlan: subscriptionPlan ?? this.subscriptionPlan,
    isActive:         isActive         ?? this.isActive,
  );

  /// Badge label for subscription tier
  String get planLabel {
    switch (subscriptionPlan) {
      case 'premium': return 'پریمیم';
      case 'standard': return 'اسٹینڈرڈ';
      default: return 'بیسک';
    }
  }
}
