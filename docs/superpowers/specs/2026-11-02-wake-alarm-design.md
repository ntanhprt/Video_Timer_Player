# Video Timer Player — Báo thức nhạc YouTube đánh thức cả nhà (thiết kế)

Ngày: 2026-11-02 · Trạng thái: **bản nháp chờ duyệt** · Nền tảng: Android (Flutter) · Build: GitHub Actions → APK → adb cài lên điện thoại

## 1. Mục đích
Hẹn giờ bật nhạc từ link YouTube, âm lượng **tăng dần** từ nhỏ đến ngưỡng đã đặt, phát qua loa Bluetooth hoặc loa cắm dây, để đánh thức cả nhà nhẹ nhàng và chắc chắn.

Thước đo thành công: **sáng nào báo thức cũng kêu đúng giờ**, kể cả khi không có mạng, điện thoại đang khóa/Doze, hoặc loa Bluetooth chưa kết nối.

### Không làm (non-goals)
- Không làm trình phát YouTube đầy đủ (tìm kiếm, playlist, đăng nhập).
- Không hỗ trợ iOS ở bản đầu.
- Không phát hành lên Play Store ở bản đầu (dùng cài tay qua adb).

### Điều gây thất bại dù app vẫn chạy
Báo thức không kêu, hoặc kêu to đột ngột lúc đang ngủ, hoặc im lặng vì loa chưa nối mà không ai biết.

## 2. Quyết định kiến trúc chính

### 2.1 Nhạc phát từ file đã tải sẵn, không stream lúc báo thức (quan trọng nhất)
Stream YouTube lúc 6h sáng dễ hỏng: không có mạng, URL stream hết hạn, thư viện trích xuất bị YouTube làm hỏng (có issue thực tế về lỗi `null check` trong `youtube_explode_dart`). Vì vậy:
- Khi lưu báo thức, app **tải audio về bộ nhớ máy** (cache).
- Đêm trước (và ~10 phút trước giờ báo), một job nền kiểm tra file còn nguyên, nếu hỏng thì tải lại.
- Lúc báo thức chỉ phát **file cục bộ**.
- Chuỗi dự phòng: file YouTube đã tải → file nhạc tải dự phòng người dùng chọn → **chuông có sẵn trong app**. Báo thức luôn kêu.

> **Rủi ro cần anh biết:** tải/trích xuất audio từ YouTube không nằm trong điều khoản của YouTube và có thể ngừng hoạt động khi YouTube đổi. Dùng cho cá nhân thì chấp nhận được, nhưng không nên đưa lên Play Store. Cách hợp lệ duy nhất (IFrame Player) không chạy ổn lúc khóa màn hình nên không dùng làm đường chính. Mô-đun lấy audio được tách riêng để thay thế khi cần.

### 2.2 Đặt giờ chính xác
- `AlarmManager.setAlarmClock()` hoặc exact alarm, kèm quyền `SCHEDULE_EXACT_ALARM` (Android 12+) / `USE_EXACT_ALARM` nếu đủ điều kiện, và `USE_FULL_SCREEN_INTENT` (Android 14+).
- Khi báo thức nổ: **foreground service** giữ phát nhạc + wake lock, hiện màn hình báo thức trên màn khóa.
- Đặt lại toàn bộ báo thức sau khi khởi động lại máy (`BOOT_COMPLETED`).
- Màn hình hướng dẫn lần đầu: tắt tối ưu pin cho app, cấp quyền exact alarm/thông báo (một số hãng như Xiaomi/Oppo cần bật thêm "tự khởi động").
- Thư viện: đánh giá `alarm` / `alarm_plus` (có exact alarm, foreground service, fade âm lượng theo bước). **Fade liên tục thì tự làm** trên player (xem 2.3). Chốt thư viện ở bước plan.

### 2.3 Tăng âm lượng thông minh
Tham số mỗi báo thức:
| Tham số | Ý nghĩa | Mặc định |
|---|---|---|
| Âm khởi đầu | mức bắt đầu (0–100%) | 0% |
| Âm đích | ngưỡng tối đa | 70% |
| Thời gian tăng | ví dụ 30s, 2 phút, 10 phút | 60s |
| Đường cong | tuyến tính / mượt (ease-in) / chậm đầu nhanh cuối | ease-in |
| Thời gian giữ | phát bao lâu rồi tự dừng | 30 phút |

Cách thực hiện: **đặt âm lượng hệ thống (kênh media) ở mức cố định ngay khi báo thức bắt đầu** rồi tăng/giảm **âm lượng trong player** (0.0–1.0) theo đường cong. Nhờ vậy cùng một cách chạy với cả loa Bluetooth lẫn loa có dây, không phụ thuộc "absolute volume" của từng loa. Khôi phục âm lượng hệ thống cũ sau khi dừng.

### 2.4 Đường ra loa
- Dùng kênh **media** để âm thanh đi theo thiết bị đang nối (Bluetooth/jack), không dùng kênh alarm (kênh này hay bị ép ra loa trong máy).
- **Lúc đặt**: người dùng chọn đầu ra mong muốn (loa trong / Bluetooth / có dây / bất kỳ đang nối).
- **Trước giờ báo ~10 phút**: kiểm tra đầu ra đã nối chưa. Nếu loa Bluetooth chưa nối, đẩy thông báo "Loa chưa kết nối" kèm hướng dẫn.
- **Lúc báo thức**: nếu đầu ra mong muốn vẫn vắng, **vẫn phát bằng loa trong máy**, không bao giờ im lặng.
- Nếu loa Bluetooth tự ngắt giữa chừng, tự chuyển sang loa trong.

## 3. Các loại hẹn giờ
1. **Một lần** vào giờ H.
2. **Lặp theo thứ** (T2–CN), có thể có hồ sơ khác cho ngày thường/cuối tuần.
3. **Đánh thức theo bậc cho cả nhà**: nhiều "mốc" trong một chuỗi, mỗi mốc có bài, âm đích và thời gian tăng riêng. Ví dụ 6:00 nhạc nhẹ tăng 10 phút; 6:20 nhạc sôi động tăng 2 phút; 6:30 âm đích 100%. Đây là phần "thông minh" chính.
4. **Hẹn sau X phút** (đếm ngược, như hẹn giờ nấu ăn).
5. **Lặp mỗi N phút trong khung giờ** (ví dụ 6:00–7:00 cứ 10 phút phát lại).
6. **Nhắc ngủ**: hẹn giờ tắt dần nhạc để ru ngủ, tức fade-out khi tới giờ (tùy chọn, ưu tiên thấp).

Mỗi báo thức có: tên, link YouTube (cắt đoạn bắt đầu/kết thúc được), phát lặp, bài dự phòng, đầu ra loa, các tham số âm lượng ở 2.3.

## 4. Hành vi khi báo thức kêu
- Màn hình khóa hiện: tên báo thức, giờ, nút **Dừng**, **Báo lại (5/10 phút)**, nút **Nhỏ lại tạm 1 phút**.
- Báo lại phát lại từ âm khởi đầu và tăng dần lại, không bật to đột ngột.
- Trong lúc kêu, **giữ âm lượng đã chọn** (không cho nút vật lý giảm về 0 mà vô tình tắt tiếng), vì mục tiêu là đánh thức.
- Tự dừng sau "thời gian giữ"; nếu không ai dừng, đẩy thông báo "Báo thức chưa được tắt".
- Nếu có cuộc gọi đến, tạm dừng và tiếp tục sau.

## 5. Màn hình
1. **Danh sách báo thức** (bật/tắt nhanh, giờ kế tiếp, đầu ra loa).
2. **Soạn báo thức** (giờ, kiểu lặp, dán link YouTube + xem trước, đường cong âm lượng có hình minh họa, chọn loa, bài dự phòng).
3. **Nghe thử** (phát thử bằng đúng đường cong, tua nhanh thời gian tăng để kiểm tra).
4. **Màn hình báo thức** (trên màn khóa).
5. **Cài đặt/Sức khỏe** (kiểm tra quyền, tối ưu pin, tình trạng cache từng báo thức, lần chạy gần nhất thành công hay không).

Lưu dữ liệu cục bộ bằng SQLite/Drift hoặc Hive; không cần máy chủ.

## 6. Kiểm thử và triển khai
- Logic thuần (đường cong âm lượng, tính giờ kế tiếp, chuỗi dự phòng) viết bằng Dart có unit test, chạy trong CI.
- CI GitHub Actions: `flutter analyze`, `flutter test`, build APK, upload artifact.
- Kiểm thử thật: `deploy.sh` tải APK từ CI rồi `scp` + `adb install -r` lên điện thoại qua máy Zorin (`anhnt@192.168.1.231`).
- Test thật bắt buộc trước khi tin dùng: khóa màn hình, Doze qua đêm, tắt mạng, tắt Bluetooth, khởi động lại máy.
- Keystore ký cố định lưu trong GitHub Secrets để cập nhật đè lên bản cũ.

## 7. Các lựa chọn em tự quyết (anh xem lại)
- Flutter, chỉ Android.
- Phát từ file đã tải sẵn thay vì stream trực tiếp.
- Âm lượng hệ thống cố định + fade ở player.
- Mặc định: đích 70%, tăng 60s, ease-in, giữ 30 phút.
- Không phát hành Play Store.

## 8. Việc để người xây dựng quyết
- Chọn thư viện báo thức và thư viện trích xuất audio (kiểm tra bản mới nhất lúc làm).
- Lược đồ lưu trữ.
- Giao diện chi tiết.

## 9. Thứ tự làm đề xuất
1. Khung Flutter + CI + `deploy.sh`, cài thử bản "Hello" lên điện thoại.
2. Phát file cục bộ với fade âm lượng + nghe thử.
3. Đặt báo thức chính xác + foreground service + màn khóa + khởi động lại.
4. Tải audio YouTube + cache + chuỗi dự phòng.
5. Kiểm tra loa Bluetooth, các loại hẹn giờ còn lại, báo thức theo bậc.
6. Web quản trị PHP + SQLite và đồng bộ với app (mục 10). Phần API sync có thể làm song song từ bước 3.

## 10. Web quản trị cấu hình (PHP thuần + SQLite3)

### 10.1 Mục đích
Chỉnh báo thức từ web (điện thoại khác, máy tính) mà không cần mở app. Web đặt tại `https://aisolutions.vn/alarm` (đường dẫn gốc **cấu hình được**, không hardcode). Tự viết, không dùng framework.

### 10.2 Nguyên tắc: báo thức không bao giờ phụ thuộc mạng
App **giữ bản sao đầy đủ cấu hình trong máy** và đặt báo thức từ bản sao đó. Web chỉ là nơi sửa và nơi lưu bản gốc. Không có mạng, máy chủ sập hay web lỗi thì báo thức vẫn kêu đúng như lần đồng bộ cuối.

### 10.3 Đồng bộ
- App kéo cấu hình từ web: khi mở app, theo chu kỳ nền (WorkManager, ví dụ 15–30 phút), và **trước giờ báo thức kế tiếp ~10 phút** (cùng job kiểm tra cache và loa ở 2.1/2.4). Không dùng Firebase/push để không phụ thuộc bên thứ ba.
- Hai chiều: sửa trên app thì đẩy lên web. Mỗi báo thức có `rev` (số tăng dần) và `updated_at`; **bản mới hơn thắng** (last-writer-wins). Xóa dùng cờ `deleted` để thiết bị khác biết mà xóa theo.
- Sau mỗi lần kéo, nếu cấu hình đổi thì đặt lại báo thức hệ thống và tải audio mới cho link mới. Việc tải/phát audio YouTube **vẫn nằm trên điện thoại**, web chỉ lưu link.
- **Chống thay đổi nguy hiểm:** chỉnh sửa trên web có hiệu lực từ lần đồng bộ kế tiếp. Nếu sửa một báo thức sắp kêu trong vòng ~15 phút, app báo cho người dùng khi áp dụng, để không bị đổi giờ bất ngờ lúc đang ngủ.
- Cài đặt app có ô **"URL máy chủ"** (mặc định trống/`https://aisolutions.vn/alarm`), nút kiểm tra kết nối, và thời điểm đồng bộ gần nhất. Bỏ trống thì app chạy độc lập hoàn toàn.

### 10.4 Giao diện web (PHP thuần)
- Đăng nhập quản trị, danh sách báo thức, soạn/sửa/xóa/bật-tắt (cùng tham số như app: giờ, kiểu lặp, link YouTube, đường cong âm lượng, đầu ra loa, bài dự phòng).
- Trang **thiết bị**: danh sách điện thoại đã ghép, lần đồng bộ gần nhất, thu hồi token.
- Trang **nhật ký**: lần báo thức chạy gần nhất của từng thiết bị (app báo lên: đã kêu / lỗi / dùng dự phòng). Giúp biết sáng nay có hỏng không.
- Dùng được trên điện thoại (responsive), không cần JS nặng.

### 10.5 API cho app
JSON qua HTTPS, ví dụ `GET /api/sync?since=<rev>`, `POST /api/alarms`, `POST /api/report`. Mỗi thiết bị có **token riêng**, tạo ở trang thiết bị, lưu dạng băm trên máy chủ.

### 10.6 Dữ liệu SQLite (tối thiểu)
`alarms` (id, name, schedule_json, youtube_url, volume_json, output, fallback, enabled, rev, updated_at, deleted), `devices` (id, name, token_hash, last_sync_at), `reports` (device_id, alarm_id, fired_at, status, detail), `users` (username, password_hash).

### 10.7 Bảo mật và triển khai
- Bắt buộc HTTPS. Mật khẩu `password_hash`, phiên có cookie `HttpOnly`/`Secure`/`SameSite`, CSRF token trên form, câu lệnh tham số hóa (PDO prepared), giới hạn số lần đăng nhập sai và số request API.
- File `.sqlite` **đặt ngoài thư mục web** nếu hosting cho phép, nếu không thì chặn truy cập trực tiếp bằng cấu hình máy chủ và đặt tên khó đoán.
- Đường dẫn gốc, đường dẫn DB, token… ở file cấu hình riêng, **không commit** bí mật.
- Cần máy chủ có PHP 8.x với `pdo_sqlite`; ghi được vào thư mục DB; sao lưu file DB định kỳ.
- Cấu trúc repo: thư mục `web/` cạnh app Flutter, hoặc repo riêng (chốt ở bước plan).

### 10.8 Giả định em đặt ra (cần anh xác nhận)
- **Một chủ sở hữu** (một tài khoản quản trị), nhiều thiết bị. Nếu cả nhà cùng có tài khoản riêng thì thêm vai trò ở bước sau.
- Hai chiều thay vì chỉ web → app (em chọn hai chiều vì tiện, đổi lại phải xử lý xung đột).
- Chưa biết `aisolutions.vn` chạy máy chủ gì (Apache/Nginx), có `pdo_sqlite` hay không, và em chưa có quyền truy cập để đưa lên đó. Em chỉ triển khai sau khi anh cho cách truy cập và đồng ý.
