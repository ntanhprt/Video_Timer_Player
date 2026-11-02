import 'alarm.dart';
import 'schedule.dart';
import 'volume_curve.dart';

/// Human-readable (Vietnamese) problems with [a]; empty when the alarm is valid.
List<String> validate(Alarm a) {
  final errors = <String>[];

  for (var i = 0; i < a.youtubeUrls.length; i++) {
    final url = a.youtubeUrls[i];
    if (url.trim().isNotEmpty && !_isYoutubeUrl(url)) {
      final which = a.youtubeUrls.length > 1 ? 'Liên kết ${i + 1}' : 'Liên kết';
      errors.add('$which phải là địa chỉ YouTube (youtube.com hoặc youtu.be).');
    }
  }
  errors.addAll(_volumeErrors(a.volume));

  switch (a.schedule) {
    case OneShot():
    case Countdown():
      break;
    case Weekly(:final weekdays):
      if (weekdays.isEmpty) errors.add(_noDays);
    case Windowed w:
      if (w.weekdays.isEmpty) errors.add(_noDays);
      if (w.every < const Duration(minutes: 1)) errors.add('Khoảng lặp phải từ 1 phút trở lên.');
      if (w.from.totalMinutes > w.to.totalMinutes) errors.add('Giờ bắt đầu khung phải trước giờ kết thúc.');
    case Staged s:
      if (s.weekdays.isEmpty) errors.add(_noDays);
      if (s.stages.isEmpty) errors.add('Cần ít nhất một mốc đánh thức.');
      for (var i = 0; i < s.stages.length; i++) {
        final st = s.stages[i];
        for (final e in _volumeErrors(st.volume)) {
          errors.add('Mốc ${i + 1}: $e');
        }
        final url = st.youtubeUrl;
        if (url != null && url.trim().isNotEmpty && !_isYoutubeUrl(url)) {
          errors.add('Mốc ${i + 1}: liên kết phải là địa chỉ YouTube.');
        }
      }
  }
  return errors;
}

const _noDays = 'Hãy chọn ít nhất một ngày trong tuần.';

List<String> _volumeErrors(VolumeSpec v) {
  final e = <String>[];
  if (v.start < 0 || v.start > 1 || v.target < 0 || v.target > 1) {
    e.add('Âm lượng phải nằm trong khoảng 0–100%.');
  } else if (v.target < v.start) {
    e.add('Âm lượng đích phải lớn hơn hoặc bằng âm lượng khởi đầu.');
  } else if (v.target == 0) {
    e.add('Âm lượng đích bằng 0 thì báo thức sẽ không có tiếng.');
  }
  if (v.ramp.isNegative) e.add('Thời gian tăng âm lượng không được âm.');
  if (v.hold <= Duration.zero) {
    e.add('Thời gian phát phải lớn hơn 0.');
  } else if (v.ramp > v.hold) {
    e.add('Thời gian tăng không được dài hơn thời gian phát.');
  }
  return e;
}

bool _isYoutubeUrl(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || (u.scheme != 'http' && u.scheme != 'https')) return false;
  final h = u.host.toLowerCase();
  return h == 'youtu.be' || h == 'youtube.com' || h.endsWith('.youtube.com');
}
