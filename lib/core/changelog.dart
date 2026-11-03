/// What changed in each version, newest first. Shown on the "Phiên bản" screen.
/// Add an entry here (and bump `version:` in pubspec.yaml) with every user-visible change.
typedef ChangelogEntry = ({String version, String date, List<String> changes});

const changelog = <ChangelogEntry>[
  (
    version: '0.5.0',
    date: '03/11/2026',
    changes: [
      'Nhận dạng giọng nói tiếng Việt tốt hơn nhiều: đổi từ Vosk (mô hình nhỏ, sai nhiều) sang mô hình Gipformer 1.5 (Zipformer 68M chuyên tiếng Việt, giấy phép MIT, chạy bằng sherpa-onnx), vẫn chạy ngoại tuyến trong máy, có dấu đầy đủ. Hiểu câu nói tự do rồi mới tách lệnh "tắt chuông", "X phút nữa báo lại".',
    ],
  ),
  (
    version: '0.4.3',
    date: '03/11/2026',
    changes: [
      'Màn hình "Micro & giọng nói" (biểu tượng micro ở thanh trên): chọn nguồn micro (micro máy, tai nghe/loa cắm dây, USB, Bluetooth...) và thử ngay, hiện thanh âm lượng và chữ nghe được.',
    ],
  ),
  (
    version: '0.4.2',
    date: '03/11/2026',
    changes: [
      'Giọng nói: luôn dùng micro của máy (trước đó cắm dây loa làm Android chuyển sang micro tai nghe nên không thu được tiếng).',
      'Màn hình báo thức hiện toàn bộ chữ nhận dạng được: câu đang nói và vài câu gần nhất, kèm tên micro đang dùng.',
    ],
  ),
  (
    version: '0.4.0',
    date: '03/11/2026',
    changes: [
      'Tự dừng báo thức khi hết "Phát tối đa" (ví dụ bài dài 1 tiếng nhưng đặt 30 phút thì 30 phút là dừng). Báo lại sau thì tính lại từ đầu.',
      'Điều khiển bằng giọng nói khi chuông đang kêu, nhận dạng NGOẠI TUYẾN trong máy (Vosk, không cần Google hay mạng): nói "tắt chuông đi" để tắt, "mười phút nữa báo lại" (hoặc "một tiếng nữa báo lại", "nửa tiếng nữa báo lại") để báo lại. Cần cấp quyền micro. Màn hình báo thức có biểu tượng micro nhấp nháy theo tiếng nói và hiện câu app nghe được.',
    ],
  ),
  (
    version: '0.3.1',
    date: '03/11/2026',
    changes: [
      'Màn hình chính: mỗi báo thức là một thẻ đầy đủ thông tin: giờ lớn, các ngày lặp, lần kêu tiếp theo (còn bao lâu), âm lượng bắt đầu → tối đa, thời gian tăng và kiểu tăng, thời gian phát tối đa, loa phát, số bài nhạc và chế độ phát.',
    ],
  ),
  (
    version: '0.3.0',
    date: '03/11/2026',
    changes: [
      'Màn hình báo thức có đồng hồ lớn (giờ:phút:giây, ngày tháng).',
      'Nút "Báo lại sau" 5, 10, 15, 20, 30 phút và 1 giờ.',
      'Hiện phiên bản và mục "Có gì mới" trong app.',
      'Màn hình báo thức: nút TẮT và 6 nút báo lại sau rất to, phủ kín màn hình, dễ bấm khi còn ngái ngủ.',
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
