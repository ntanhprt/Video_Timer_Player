/// What changed in each version, newest first. Shown on the "Phiên bản" screen.
/// Add an entry here (and bump `version:` in pubspec.yaml) with every user-visible change.
typedef ChangelogEntry = ({String version, String date, List<String> changes});

const changelog = <ChangelogEntry>[
  (
    version: '0.8.4',
    date: '11/11/2026',
    changes: [
      'Nút "Lưu" khi tạo/sửa báo thức nằm ở góc trên bên phải, dễ bấm. Sửa lỗi bấm Lưu xong vẫn hỏi "Chưa lưu, ở lại hay thoát"; "Thoát, bỏ thay đổi" và "Xóa" cũng không còn hỏi lại.',
      'Nhạc dùng chung cho mọi báo thức: nút "Chọn từ nhạc đã tải / đã có trong máy" liệt kê mọi bài YouTube đã tải và file đã chọn, tích nhiều bài để thêm vào danh sách của báo thức đang sửa.',
    ],
  ),
  (
    version: '0.8.3',
    date: '10/11/2026',
    changes: [
      'Tự phát hiện báo thức bị hệ thống xóa: khi mở app, nếu các báo thức đang bật không còn được đăng ký với Android (app từng bị dừng hẳn, thường do MIUI dọn bộ nhớ), màn hình chính hiện cảnh báo đỏ "Báo thức có thể đã bị lỡ" cho đến khi anh bấm "Đã hiểu"; app tự đăng ký lại ngay.',
      'Cảnh báo sớm khi thiếu quyền làm báo thức kém tin cậy (thông báo, báo thức chính xác, pin không hạn chế) kèm nút mở cài đặt app.',
    ],
  ),
  (
    version: '0.8.2',
    date: '05/11/2026',
    changes: [
      'Bỏ nghe giọng nói khi chuông kêu: chuông chỉ phát nhạc theo cấu hình, anh tắt hoặc báo lại bằng tay. Không còn mở micro nên không thể ảnh hưởng đến việc phát nhạc.',
    ],
  ),
  (
    version: '0.8.1',
    date: '04/11/2026',
    changes: [
      'Màn hình chính có đồng hồ lớn (giờ:phút:giây và ngày) ở trên cùng, để tắt chuông xong vẫn xem giờ được.',
      'Nghe lệnh khi nhạc đang kêu: bật khử vọng và giảm ồn của máy, coi tiếng nhạc đều là nền để tìm chỗ anh nói, và cứ 4 giây lại nhận dạng một lần thay vì chờ im lặng. Có công tắc "Lọc tiếng nhạc khi nghe" trong trang Micro & giọng nói để so sánh bật/tắt.',
    ],
  ),
  (
    version: '0.8.0',
    date: '03/11/2026',
    changes: [
      'Tuya: danh sách thiết bị. Thêm nhiều ổ cắm, mỗi thiết bị có nút BẬT/TẮT nhanh và các hẹn giờ riêng (chọn giờ, bật hay tắt, các ngày trong tuần), giống app Tuya.',
      'Hẹn giờ chạy đúng giờ kể cả khi app đang đóng (app tự thức dậy, thử lại 3 lần nếu wifi chưa sẵn sàng) và ghi lại "Hẹn giờ đã chạy gần đây". Đặt giờ BẬT sớm hơn báo thức để loa kịp khởi động.',
      'Trang "Hướng dẫn kết nối Tuya" trong app: xem Device ID và IP trong app Tuya, lấy Local key ở iot.tuya.com hoặc bằng TinyTuya.',
      'Giao thức Tuya LAN 3.3 và 3.4 (kiểm tra từng byte với TinyTuya). Đã bỏ cấu hình một ổ cắm của bản 0.7.0; dữ liệu cũ tự chuyển thành một thiết bị.',
    ],
  ),
  (
    version: '0.6.0',
    date: '03/11/2026',
    changes: [
      'Hệ thống lệnh giọng nói mở rộng được: mỗi lệnh là một khai báo (mẫu câu, tham số, hành động) đăng ký vào bộ lệnh; thêm lệnh mới không cần sửa phần còn lại. Khớp mờ để chịu lỗi nhận dạng.',
      'Lệnh mới: "mấy giờ rồi", "các lệnh", "dậy rồi" (tắt), "mười phút nữa" (báo lại).',
      'Tự học lệnh: câu app nghe mà chưa hiểu hiện trong trang Micro & giọng nói; bấm vào để dạy nó làm "Tắt chuông" hoặc "Báo lại N phút". Lệnh đã dạy được lưu và xóa được.',
    ],
  ),
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
