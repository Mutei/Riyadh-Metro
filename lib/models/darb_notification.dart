enum DarbNotificationType { trip, transfer, service, general }

class DarbNotification {
  const DarbNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.isRead,
    this.readAt,
    this.relatedTripId,
  });

  final String id;
  final DarbNotificationType type;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;
  final DateTime? readAt;
  final String? relatedTripId;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'type': type.name,
        'title': title,
        'message': message,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'isRead': isRead,
        'readAt': readAt?.millisecondsSinceEpoch,
        'relatedTripId': relatedTripId,
      };

  factory DarbNotification.fromMap(String id, Map<Object?, Object?> map) {
    final typeName = map['type']?.toString();
    final type = DarbNotificationType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => DarbNotificationType.general,
    );
    final createdAtMillis = (map['createdAt'] as num?)?.toInt() ?? 0;
    final readAtMillis = (map['readAt'] as num?)?.toInt();
    return DarbNotification(
      id: id,
      type: type,
      title: map['title']?.toString() ?? '',
      message: map['message']?.toString() ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMillis),
      isRead: map['isRead'] as bool? ?? false,
      readAt: readAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(readAtMillis),
      relatedTripId: map['relatedTripId']?.toString(),
    );
  }
}
