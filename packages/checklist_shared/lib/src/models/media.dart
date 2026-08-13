class MediaEntry {
  const MediaEntry({
    required this.url,
    this.timestamp,
    this.type = 'image',
    this.name,
  });

  final String url;
  final int? timestamp;
  final String type;
  final String? name;

  bool get isRemote => url.startsWith('http://') || url.startsWith('https://');

  Map<String, dynamic> toMap() => {
    'url': url,
    'timestamp': timestamp ?? DateTime.now().millisecondsSinceEpoch,
    'type': type,
    'name': name ?? 'media',
  };

  factory MediaEntry.fromDynamic(dynamic value, {int index = 0}) {
    if (value is String) {
      final isVideo =
          value.startsWith('data:video') ||
          RegExp(
            r'\.(mp4|webm|ogg|mov|m4v)(\?|#|$)',
            caseSensitive: false,
          ).hasMatch(value);
      return MediaEntry(
        url: value,
        timestamp: DateTime.now().millisecondsSinceEpoch + index,
        type: isVideo ? 'video' : 'image',
        name: 'media_${DateTime.now().millisecondsSinceEpoch}_$index',
      );
    }
    if (value is Map) {
      final map = <String, dynamic>{
        for (final e in value.entries) '${e.key}': e.value,
      };
      final mediaUrl = (map['url'] ?? map['dataUrl'] ?? '').toString();
      final explicit = (map['type'] ?? '').toString().toLowerCase();
      String mediaType = 'image';
      if (explicit.startsWith('video')) {
        mediaType = 'video';
      } else if (explicit.startsWith('image')) {
        mediaType = 'image';
      } else if (mediaUrl.startsWith('data:video') ||
          RegExp(
            r'\.(mp4|webm|mov|m4v)(\?|#|$)',
            caseSensitive: false,
          ).hasMatch(mediaUrl)) {
        mediaType = 'video';
      }
      final ts = map['timestamp'];
      return MediaEntry(
        url: mediaUrl,
        timestamp: ts is num
            ? ts.toInt()
            : int.tryParse('$ts') ??
                  DateTime.now().millisecondsSinceEpoch + index,
        type: mediaType,
        name:
            map['name']?.toString() ??
            'media_${DateTime.now().millisecondsSinceEpoch}_$index',
      );
    }
    return MediaEntry(
      url: '',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class ItemMedia {
  const ItemMedia({this.issue = const [], this.fix = const []});

  final List<MediaEntry> issue;
  final List<MediaEntry> fix;

  ItemMedia copyWith({List<MediaEntry>? issue, List<MediaEntry>? fix}) =>
      ItemMedia(issue: issue ?? this.issue, fix: fix ?? this.fix);

  Map<String, dynamic> toMap() => {
    'issue': issue.map((e) => e.toMap()).toList(),
    'fix': fix.map((e) => e.toMap()).toList(),
  };

  factory ItemMedia.fromDynamic(dynamic value) {
    if (value is Map &&
        (value.containsKey('issue') ||
            value.containsKey('fix') ||
            value.containsKey('url'))) {
      return ItemMedia(
        issue: _asMediaList(value['issue'] ?? value['url']),
        fix: _asMediaList(value['fix']),
      );
    }
    return ItemMedia(issue: _asMediaList(value), fix: const []);
  }

  static List<MediaEntry> _asMediaList(dynamic value) {
    if (value == null) return const [];
    final list = value is List ? value : [value];
    return [
      for (var i = 0; i < list.length; i++)
        MediaEntry.fromDynamic(list[i], index: i),
    ].where((e) => e.url.isNotEmpty).toList();
  }
}

Map<String, ItemMedia> normalizeImagesMap(dynamic value) {
  final output = <String, ItemMedia>{};
  if (value is! Map) return output;
  value.forEach((key, entry) {
    output['$key'] = ItemMedia.fromDynamic(entry);
  });
  return output;
}

Map<String, dynamic> imagesMapToFirestore(Map<String, ItemMedia> images) {
  return {for (final e in images.entries) e.key: e.value.toMap()};
}

String buildDailyRecordId(String buildingId, String date) =>
    '${buildingId}__$date';

String todayLocalDate() {
  final now = DateTime.now();
  final local = now.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String nowLocalTime() {
  final local = DateTime.now().toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
