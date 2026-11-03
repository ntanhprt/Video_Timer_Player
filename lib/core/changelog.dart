/// What changed in each version, newest first. Shown on the "Phiên bản" screen.
/// Add an entry here (and bump `version:` in pubspec.yaml) with every user-visible change.
typedef ChangelogEntry = ({String version, String date, List<String> changes});

const changelog = <ChangelogEntry>[
  (
    version: '0.3.0',
    date: '03/11/2026',
    changes: [
      'Màn hình báo thức có đồng hồ lớn (giờ:phút:giây, ngày tháng).',
      'Nút "Báo lại sau" 5, 10, 15, 20, 30 phút và 1 giờ.',
      'Hiện phiên bản và mục "Có gì mới" trong app.',
      'Cập nhật app không làm mất báo thức và nhạc đã tải (khóa ký cố định).',
    ],
  ),
  (
    version: '0.2.0',
    date: '03/11/2026',
    changes: [
      'Tải nhạc YouTube bằng yt-dlp (tự cập nhật trước mỗi lần tải), chỉ lấy âm thanh, tối đa 64 MB mỗi bài.',
      'Nút "Tải ngay" và cửa sổ log từng bước.',
      'Chọn nhiều file nhạc trong máy.',
      'Danh sách nhạc: tên video, trạng thái đã tải / chưa tải, nghe thử, loại bỏ.',
      'Chọn phát ngẫu nhiên hoặc theo thứ tự.',
    ],
  ),
  (
    version: '0.1.0',
    date: '02/11/2026',
    changes: [
      'Báo thức hẹn giờ theo tuần, âm lượng tăng dần (chỉnh thời gian và đường cong).',
      'Nhiều link YouTube mỗi báo thức, nút Lưu và cảnh báo khi thoát chưa lưu.',
      'Màn hình báo thức toàn màn hình với nút TẮT.',
    ],
  ),
];
