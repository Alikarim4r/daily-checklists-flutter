class ClientErrorLog {
  const ClientErrorLog({
    required this.id,
    required this.userId,
    required this.appKey,
    required this.errorType,
    required this.errorMessage,
    required this.occurredAt,
    this.appVersion = '',
    this.buildNumber = '',
    this.platform = '',
    this.module = '',
    this.stackSummary = '',
  });

  final int id;
  final String userId;
  final String appKey;
  final String appVersion;
  final String buildNumber;
  final String platform;
  final String module;
  final String errorType;
  final String errorMessage;
  final String stackSummary;
  final DateTime occurredAt;

  factory ClientErrorLog.fromJson(Map<String, dynamic> json) => ClientErrorLog(
    id: (json['id'] as num).toInt(),
    userId: (json['user_id'] ?? '') as String,
    appKey: (json['app_key'] ?? '') as String,
    appVersion: (json['app_version'] ?? '') as String,
    buildNumber: (json['build_number'] ?? '') as String,
    platform: (json['platform'] ?? '') as String,
    module: (json['module'] ?? '') as String,
    errorType: (json['error_type'] ?? '') as String,
    errorMessage: (json['error_message'] ?? '') as String,
    stackSummary: (json['stack_summary'] ?? '') as String,
    occurredAt: DateTime.parse(json['occurred_at'] as String),
  );
}
