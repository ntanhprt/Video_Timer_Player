import 'schedule.dart';
import 'volume_curve.dart';

enum OutputKind { speaker, bluetooth, wired, anyConnected }

class Alarm {
  final String id;
  final String name;
  final ScheduleSpec schedule;

  /// Empty means "no YouTube track": the fallback chain plays instead.
  final String youtubeUrl;
  final VolumeSpec volume;
  final OutputKind output;
  final String? fallbackPath;
  final bool enabled;

  /// Revision counter used by sync; the higher revision wins.
  final int rev;
  final DateTime updatedAt;

  /// Soft delete so other devices learn about the removal during sync.
  final bool deleted;

  const Alarm({
    required this.id,
    required this.name,
    required this.schedule,
    required this.youtubeUrl,
    required this.volume,
    required this.output,
    this.fallbackPath,
    required this.enabled,
    required this.rev,
    required this.updatedAt,
    this.deleted = false,
  });

  Alarm copyWith({
    String? name,
    ScheduleSpec? schedule,
    String? youtubeUrl,
    VolumeSpec? volume,
    OutputKind? output,
    String? fallbackPath,
    bool? enabled,
    int? rev,
    DateTime? updatedAt,
    bool? deleted,
  }) =>
      Alarm(
        id: id,
        name: name ?? this.name,
        schedule: schedule ?? this.schedule,
        youtubeUrl: youtubeUrl ?? this.youtubeUrl,
        volume: volume ?? this.volume,
        output: output ?? this.output,
        fallbackPath: fallbackPath ?? this.fallbackPath,
        enabled: enabled ?? this.enabled,
        rev: rev ?? this.rev,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'schedule': schedule.toJson(),
        'youtubeUrl': youtubeUrl,
        'volume': volume.toJson(),
        'output': output.name,
        'fallbackPath': fallbackPath,
        'enabled': enabled,
        'rev': rev,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deleted': deleted,
      };

  factory Alarm.fromJson(Map<String, dynamic> j) => Alarm(
        id: j['id'] as String,
        name: j['name'] as String,
        schedule: ScheduleSpec.fromJson(j['schedule'] as Map<String, dynamic>),
        youtubeUrl: j['youtubeUrl'] as String,
        volume: VolumeSpec.fromJson(j['volume'] as Map<String, dynamic>),
        output: OutputKind.values.byName(j['output'] as String),
        fallbackPath: j['fallbackPath'] as String?,
        enabled: j['enabled'] as bool,
        rev: j['rev'] as int,
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        deleted: j['deleted'] as bool? ?? false,
      );
}
