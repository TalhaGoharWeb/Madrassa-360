/// درجہ / کلاس ماڈل
/// Darja — a class/level in the madrasa curriculum

class Darja {
  final String? id;
  final String tenantId;   // multi-tenant owner (public.tenants) — required
  final String? madrasaId; // DEPRECATED: kept for Phase-8 removal
  final String nameUrdu;
  final String nameEnglish;
  final String level;       // 'nazra' | 'hifz' | 'dars_e_nizami' | 'takhassus'
  final int orderIndex;
  final String? description;
  final int? capacity;
  final bool isActive;

  const Darja({
    this.id,
    required this.tenantId,
    this.madrasaId,
    required this.nameUrdu,
    required this.nameEnglish,
    required this.level,
    this.orderIndex = 0,
    this.description,
    this.capacity,
    this.isActive = true,
  });

  factory Darja.fromJson(Map<String, dynamic> j) => Darja(
        id:          j['id'] as String?,
        tenantId:    (j['tenant_id'] ?? j['madrasa_id'] ?? '') as String,
        madrasaId:   j['madrasa_id'] as String?,
        nameUrdu:    j['name_urdu'] as String? ?? '',
        nameEnglish: j['name_english'] as String? ?? '',
        level:       j['level'] as String? ?? 'dars_e_nizami',
        orderIndex:  j['order_index'] as int? ?? 0,
        description: j['description'] as String?,
        capacity:    j['capacity'] as int?,
        isActive:    j['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'tenant_id':    tenantId,
        'madrasa_id':   madrasaId,
        'name_urdu':    nameUrdu,
        'name_english': nameEnglish,
        'level':        level,
        'order_index':  orderIndex,
        'description':  description,
        'capacity':     capacity,
        'is_active':    isActive,
      };

  Darja copyWith({
    String? nameUrdu, String? nameEnglish,
    String? level, int? orderIndex,
    String? description, int? capacity, bool? isActive,
  }) => Darja(
    id: id, tenantId: tenantId, madrasaId: madrasaId,
    nameUrdu:    nameUrdu    ?? this.nameUrdu,
    nameEnglish: nameEnglish ?? this.nameEnglish,
    level:       level       ?? this.level,
    orderIndex:  orderIndex  ?? this.orderIndex,
    description: description ?? this.description,
    capacity:    capacity    ?? this.capacity,
    isActive:    isActive    ?? this.isActive,
  );

  String get levelLabel {
    switch (level) {
      case 'nazra':        return 'ناظرہ';
      case 'hifz':         return 'حفظ';
      case 'takhassus':    return 'تخصص';
      default:             return 'درسِ نظامی';
    }
  }
}

/// درجہ سیکشن — a section within a Darja
class DarjaSection {
  final String? id;
  final String darjaId;
  final String tenantId;   // multi-tenant owner (public.tenants) — required
  final String? madrasaId; // DEPRECATED: kept for Phase-8 removal
  final String nameUrdu;   // e.g. الف، ب، ج
  final String? teacherId; // FK → staff
  final int? capacity;
  final bool isActive;

  const DarjaSection({
    this.id,
    required this.darjaId,
    required this.tenantId,
    this.madrasaId,
    required this.nameUrdu,
    this.teacherId,
    this.capacity,
    this.isActive = true,
  });

  factory DarjaSection.fromJson(Map<String, dynamic> j) => DarjaSection(
        id:        j['id'] as String?,
        darjaId:   j['darja_id'] as String,
        tenantId:  (j['tenant_id'] ?? j['madrasa_id'] ?? '') as String,
        madrasaId: j['madrasa_id'] as String?,
        nameUrdu:  j['name_urdu'] as String? ?? '',
        teacherId: j['teacher_id'] as String?,
        capacity:  j['capacity'] as int?,
        isActive:  j['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'darja_id':   darjaId,
        'tenant_id':  tenantId,
        'madrasa_id': madrasaId,
        'name_urdu':  nameUrdu,
        'teacher_id': teacherId,
        'capacity':   capacity,
        'is_active':  isActive,
      };
}
