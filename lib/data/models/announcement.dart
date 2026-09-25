/// اعلان ماڈل
/// Announcement — notice posted by admin/teacher

enum AnnouncementTarget { all, teachers, parents, students, specific }

extension AnnouncementTargetX on AnnouncementTarget {
  String get urduLabel {
    switch (this) {
      case AnnouncementTarget.all:      return 'سب کے لیے';
      case AnnouncementTarget.teachers: return 'اساتذہ';
      case AnnouncementTarget.parents:  return 'والدین';
      case AnnouncementTarget.students: return 'طلباء';
      case AnnouncementTarget.specific: return 'مخصوص';
    }
  }
}

class Announcement {
  final String? id;
  final String tenantId;   // multi-tenant owner (public.tenants) — required
  final String? madrasaId; // DEPRECATED: kept for Phase-8 removal
  final String title;
  final String body;
  final AnnouncementTarget target;
  final String? postedByUserId;
  final String? postedByName;
  final bool isPinned;
  final DateTime? scheduledAt;
  final DateTime? createdAt;

  const Announcement({
    this.id,
    required this.tenantId,
    this.madrasaId,
    required this.title,
    required this.body,
    this.target = AnnouncementTarget.all,
    this.postedByUserId,
    this.postedByName,
    this.isPinned = false,
    this.scheduledAt,
    this.createdAt,
  });

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        id:              j['id'] as String?,
        tenantId:        (j['tenant_id'] ?? j['madrasa_id'] ?? '') as String,
        madrasaId:       j['madrasa_id'] as String?,
        title:           j['title'] as String? ?? '',
        body:            j['body'] as String? ?? '',
        target:          AnnouncementTarget.values.firstWhere(
            (t) => t.name == (j['target'] as String? ?? 'all'),
            orElse: () => AnnouncementTarget.all),
        postedByUserId:  j['posted_by_user_id'] as String?,
        postedByName:    j['posted_by_name'] as String?,
        isPinned:        j['is_pinned'] as bool? ?? false,
        scheduledAt:     j['scheduled_at'] != null
            ? DateTime.tryParse(j['scheduled_at'] as String) : null,
        createdAt:       j['created_at'] != null
            ? DateTime.tryParse(j['created_at'] as String) : null,
      );

  Map<String, dynamic> toJson() => {
        'tenant_id':         tenantId,
        'madrasa_id':         madrasaId,
        'title':              title,
        'body':               body,
        'target':             target.name,
        'posted_by_user_id':  postedByUserId,
        'posted_by_name':     postedByName,
        'is_pinned':          isPinned,
        'scheduled_at':       scheduledAt?.toIso8601String(),
      };

  Announcement copyWith({
    String? title, String? body,
    AnnouncementTarget? target, bool? isPinned,
  }) => Announcement(
    id: id, tenantId: tenantId, madrasaId: madrasaId, createdAt: createdAt,
    postedByUserId: postedByUserId, postedByName: postedByName,
    title:    title    ?? this.title,
    body:     body     ?? this.body,
    target:   target   ?? this.target,
    isPinned: isPinned ?? this.isPinned,
  );
}
