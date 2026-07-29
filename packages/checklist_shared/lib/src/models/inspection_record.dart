import 'media.dart';

class InspectionRecord {
  InspectionRecord({
    required this.id,
    required this.buildingId,
    this.buildingName = '',
    this.buildingNameAr = '',
    this.buildingPin = '',
    this.buildingType = '',
    this.technicianName = '',
    this.inspectionDate = '',
    this.inspectionTime = '',
    Map<String, String>? responses,
    Map<String, String>? remarks,
    Map<String, ItemMedia>? images,
    this.signature,
    List<Map<String, dynamic>>? customItems,
    Map<String, String>? customItemTexts,
    this.userEmail = '',
    this.recordId,
    this.createdAt,
    this.updatedAt,
    this.previousRecordId,
    this.recordMode,
    this.submittedAt,
    this.submittedBy,
    this.sourceRecordId,
    this.raw = const {},
  })  : responses = responses ?? {},
        remarks = remarks ?? {},
        images = images ?? {},
        customItems = customItems ?? [],
        customItemTexts = customItemTexts ?? {};

  final String id;
  final String buildingId;
  final String buildingName;
  final String buildingNameAr;
  final String buildingPin;
  final String buildingType;
  final String technicianName;
  final String inspectionDate;
  final String inspectionTime;
  final Map<String, String> responses;
  final Map<String, String> remarks;
  final Map<String, ItemMedia> images;
  final String? signature;
  final List<Map<String, dynamic>> customItems;
  final Map<String, String> customItemTexts;
  final String userEmail;
  final String? recordId;
  final String? createdAt;
  final String? updatedAt;
  final String? previousRecordId;
  final String? recordMode;
  final dynamic submittedAt;
  final String? submittedBy;
  final String? sourceRecordId;
  final Map<String, dynamic> raw;

  factory InspectionRecord.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    final responsesRaw = data['responses'];
    final remarksRaw = data['remarks'];
    final customTextsRaw = data['customItemTexts'];

    return InspectionRecord(
      id: id,
      buildingId: (data['buildingId'] ?? '').toString(),
      buildingName: (data['buildingName'] ?? '').toString(),
      buildingNameAr: (data['buildingNameAr'] ?? '').toString(),
      buildingPin: (data['buildingPin'] ?? '').toString(),
      buildingType: (data['buildingType'] ?? '').toString(),
      technicianName: (data['technicianName'] ?? '').toString(),
      inspectionDate: (data['inspectionDate'] ?? '').toString(),
      inspectionTime: (data['inspectionTime'] ?? '').toString(),
      responses: _stringMap(responsesRaw),
      remarks: _stringMap(remarksRaw),
      images: normalizeImagesMap(data['imageUrlsList'] ?? data['images']),
      signature: _asNullableString(data['signature']),
      customItems: _customItemsList(data['customItems']),
      customItemTexts: _stringMap(customTextsRaw),
      userEmail: (data['userEmail'] ?? '').toString(),
      recordId: data['recordId']?.toString(),
      createdAt: data['createdAt']?.toString(),
      updatedAt: data['updatedAt']?.toString(),
      previousRecordId: data['previousRecordId']?.toString(),
      recordMode: data['recordMode']?.toString(),
      submittedAt: data['submittedAt'],
      submittedBy: data['submittedBy']?.toString(),
      sourceRecordId: data['sourceRecordId']?.toString(),
      raw: data,
    );
  }

  Map<String, dynamic> toFirestoreMap({
    required bool includeCreatedAt,
    String? createdAtOverride,
  }) {
    final imagesPayload = imagesMapToFirestore(images);
    final map = <String, dynamic>{
      'buildingId': buildingId,
      'buildingName': buildingName,
      'buildingNameAr': buildingNameAr,
      'buildingPin': buildingPin,
      'buildingType': buildingType,
      'technicianName': technicianName,
      'inspectionDate': inspectionDate,
      'inspectionTime': inspectionTime,
      // Keep string keys — Firestore/Dart codec casts map keys to String.
      'responses': {
        for (final e in responses.entries) e.key: e.value,
      },
      'remarks': {
        for (final e in remarks.entries) e.key: e.value,
      },
      'images': imagesPayload,
      'imageUrlsList': imagesPayload,
      'signature': signature,
      'customItems': customItems,
      'customItemTexts': {
        for (final e in customItemTexts.entries) e.key: e.value,
      },
      'userEmail': userEmail,
      'recordId': recordId ?? id,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'previousRecordId': previousRecordId,
      'recordMode': recordMode,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    if (includeCreatedAt) {
      map['createdAt'] =
          createdAtOverride ?? DateTime.now().toUtc().toIso8601String();
    }
    return map;
  }

  static Map<String, String> _stringMap(dynamic raw) {
    if (raw is! Map) return {};
    return {
      for (final e in raw.entries)
        '${e.key}': e.value == null ? '' : '${e.value}',
    };
  }

  static String? _asNullableString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  static List<Map<String, dynamic>> _customItemsList(dynamic raw) {
    if (raw is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      out.add({
        for (final e in item.entries) '${e.key}': e.value,
      });
    }
    return out;
  }
}
