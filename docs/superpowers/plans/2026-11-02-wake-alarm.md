# Video Timer Player (Báo thức nhạc YouTube) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Android app hẹn giờ phát nhạc YouTube với âm lượng tăng dần để đánh thức cả nhà, kèm web PHP+SQLite để chỉnh cấu hình từ xa.

**Architecture:** App Flutter giữ bản sao cấu hình cục bộ (SQLite), đặt báo thức bằng AlarmManager chính xác và phát file audio đã tải sẵn qua foreground service; fade âm lượng ở player trên nền âm lượng hệ thống cố định. Web PHP thuần là nơi lưu bản gốc, app đồng bộ hai chiều bằng polling theo `rev`; báo thức không bao giờ phụ thuộc mạng.

**Tech Stack:** Flutter (Dart, chỉ Android), Kotlin (service/receiver native), SQLite (app: `drift` hoặc `sqflite`; web: PDO sqlite), `just_audio`, `youtube_explode_dart`, `workmanager`, GitHub Actions, PHP 8.x thuần.

**Spec:** `docs/superpowers/specs/2026-11-02-wake-alarm-design.md`

## Global Constraints

- Chỉ Android; không iOS, không Play Store ở bản đầu.
- Báo thức luôn kêu: chuỗi dự phòng file YouTube đã tải → bài dự phòng người dùng chọn → chuông có sẵn trong app.
- Lúc báo thức chỉ phát **file cục bộ**, không stream.
- Mặc định: âm khởi đầu 0%, âm đích 70%, thời gian tăng 60s, đường cong ease-in, giữ 30 phút.
- Phát qua kênh **media** (không dùng kênh alarm); đặt âm lượng hệ thống cố định rồi fade trong player; khôi phục âm lượng cũ khi dừng.
- Quyền: `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, foreground service, wake lock.
- Web: PHP thuần, PDO SQLite, không framework; đường dẫn gốc và đường dẫn DB cấu hình được (mặc định `https://aisolutions.vn/alarm`); HTTPS; file `.sqlite` ngoài webroot hoặc bị chặn; token thiết bị lưu dạng băm; không commit bí mật.
- URL máy chủ trong app cấu hình được; để trống thì app chạy độc lập.
- Web production: máy Windows ASUS `TA@42.118.174.22` (xem `asus_info/README.md`), KHÔNG dùng máy Linux `javis-ai` để phục vụ web.
- Máy cài thử: `anhnt@192.168.1.231` (có `adb`, điện thoại `d58de1c8`); repo `github.com/ntanhprt/Video_Timer_Player`, nhánh `main`.
- Máy phát triển không có Flutter SDK: mọi `flutter` build/test chạy trong GitHub Actions (hoặc image `ghcr.io/cirruslabs/flutter`). PHP test chạy local bằng `php`.

## Review Focus

Các đầu vào/tình huống spec ngụ ý nhưng ít người test, theo thứ tự dễ gặp nhất:
1. Máy tắt/khởi động lại **sau** giờ báo: báo thức đã lỡ phải xử lý ra sao (không kêu bù lúc quá muộn, hiện thông báo "đã lỡ"). → Task 4.
2. Link YouTube lỗi (riêng tư, bị xóa, giới hạn tuổi, playlist, link rút gọn, chỉ dán ID): phải báo lỗi rõ lúc lưu và vẫn có dự phòng lúc báo. → Task 5.
3. Tham số âm lượng vô lý (đích < đầu, đích 0, thời gian tăng 0, tăng dài hơn thời gian giữ): kiểm tra hợp lệ, không bật to đột ngột. → Task 2, 3.
4. App bị hệ thống kill giữa lúc đang fade: âm lượng hệ thống phải được khôi phục, báo thức không phát lại chồng. → Task 4.
5. Xung đột đồng bộ: hai nơi sửa cùng `rev`, đồng hồ lệch/đổi múi giờ/giờ mùa hè, payload quá lớn hoặc sai kiểu gửi lên API. → Task 7, 8.

---

### Task 1: Khung dự án, CI và triển khai thử lên điện thoại

**Files:**
- Create: `.github/workflows/bootstrap.yml`, `.github/workflows/build.yml`, `scripts/deploy.sh`, `.gitignore`, `README.md`
- Create (do bootstrap sinh): `pubspec.yaml`, `lib/main.dart`, `android/`

**Interfaces:**
- Produces: `scripts/deploy.sh` (không tham số) chạy chuỗi push → `gh run watch` → `gh run download -n app-release` → `scp` sang Zorin → `adb install -r`; in `OK` khi thành công, mã thoát ≠ 0 khi lỗi. CI artifact tên `app-release`.

- [ ] **Step 1: Tạo repo local trỏ tới `ntanhprt/Video_Timer_Player`**, nhánh `main`, commit `.gitignore` (Flutter, `build/`, `*.jks`, `key.properties`, `web/config.local.php`, `*.sqlite`).
- [ ] **Step 2: Viết `bootstrap.yml` (workflow_dispatch)**: cài Flutter stable, chạy `flutter create --platforms=android --org vn.aisolutions --project-name video_timer_player .`, commit `android/`, `pubspec.yaml`, `lib/` lên `main`. Chạy workflow bằng `gh workflow run bootstrap.yml`, kéo về (`git pull`).
- [ ] **Step 3: Viết `build.yml`** (on push + workflow_dispatch): `setup-java` 17, `subosito/flutter-action`, `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build apk --release`, upload artifact `app-release`.
- [ ] **Step 4: Tạo keystore cố định** bằng `keytool` ở máy phát triển (ngoài repo); lưu base64 + mật khẩu vào GitHub Secrets (`ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`); `build.yml` giải mã và dùng khi ký release. Giữ bản sao keystore ngoài repo, báo anh vị trí.
- [ ] **Step 5: Viết `scripts/deploy.sh`** theo Interfaces ở trên (có kiểm tra `adb devices` thấy thiết bị `device` trước khi cài).
- [ ] **Step 6: Verify:** `./scripts/deploy.sh` → CI xanh, APK "Hello" cài lên điện thoại, mở được. Lần chạy thứ hai cài đè được mà không gỡ (chứng minh chữ ký ổn định).
- [ ] **Step 7: Commit** `chore: scaffold flutter + CI + deploy script`.

### Task 2: Lõi thuần Dart — mô hình báo thức, tính giờ kế tiếp, đường cong âm lượng

**Files:**
- Create: `lib/core/alarm.dart`, `lib/core/schedule.dart`, `lib/core/volume_curve.dart`, `lib/core/validation.dart`
- Test: `test/core/schedule_test.dart`, `test/core/volume_curve_test.dart`, `test/core/validation_test.dart`

**Interfaces:**
- Produces:
  - `class Alarm { String id; String name; ScheduleSpec schedule; String youtubeUrl; VolumeSpec volume; OutputKind output; String? fallbackPath; bool enabled; int rev; DateTime updatedAt; bool deleted; }` (+ `toJson`/`fromJson`)
  - `sealed class ScheduleSpec` với `OneShot(DateTime at)`, `Weekly(TimeOfDayMin t, Set<int> weekdays)`, `Countdown(Duration d, DateTime startedAt)`, `Windowed(TimeOfDayMin from, TimeOfDayMin to, Duration every, Set<int> weekdays)`, `Staged(List<Stage> stages)`
  - `DateTime? nextFire(ScheduleSpec s, DateTime now)` (giờ địa phương, null nếu không còn lần nào)
  - `class VolumeSpec { double start; double target; Duration ramp; Curve curve; Duration hold; }`, `enum Curve { linear, easeIn, easeOut }`
  - `double volumeAt(VolumeSpec v, Duration elapsed)` trong `[0,1]`, đơn điệu không giảm, `== start` ở 0, `== target` từ `ramp` trở đi
  - `List<String> validate(Alarm a)` trả danh sách lỗi (rỗng nếu hợp lệ)

- [ ] **Step 1: Viết test lỗi** `volume_curve_test.dart`: `volumeAt` ở 0 = start; ở `ramp` = target; tại `ramp/2` với linear = giữa start–target, với easeIn < giữa; không vượt target sau `ramp`; ramp = 0 trả ngay target.
- [ ] **Step 2: Viết test lỗi** `schedule_test.dart`: Weekly T2,T4 06:30 — từ Thứ Ba 07:00 trả Thứ Tư 06:30; từ đúng 06:30:00 trả lần kế tiếp (không trả chính nó); OneShot đã qua trả null; qua ranh giới đổi giờ mùa hè vẫn giữ 06:30 địa phương; Windowed trả mốc kế tiếp trong khung và sang ngày sau khi hết khung; Staged trả mốc đầu chưa qua.
- [ ] **Step 3: Viết test lỗi** `validation_test.dart`: `target < start`, `target == 0`, `ramp < 0`, `ramp > hold`, URL không phải YouTube, `Weekly` rỗng weekdays → mỗi trường hợp có đúng một thông báo lỗi tiếng Việt cụ thể; mặc định của spec hợp lệ.
- [ ] **Step 4: Chạy test (CI), xác nhận FAIL**, rồi cài `volumeAt`, `nextFire`, `validate` theo Interfaces. Dùng `DateTime` địa phương và dựng lại mốc từ (năm, tháng, ngày, giờ, phút), không cộng `Duration` 24h (tránh lệch khi đổi giờ).
- [ ] **Step 5: Chạy test, xác nhận PASS; commit** `feat(core): alarm model, schedule, volume curve, validation`.

### Task 3: Lưu trữ cục bộ và giao diện danh sách / soạn báo thức

**Files:**
- Create: `lib/data/alarm_repository.dart`, `lib/ui/alarm_list_page.dart`, `lib/ui/alarm_edit_page.dart`, `lib/ui/curve_preview.dart`
- Modify: `lib/main.dart`
- Test: `test/data/alarm_repository_test.dart`, `test/ui/alarm_edit_page_test.dart`

**Interfaces:**
- Consumes: `Alarm`, `validate`, `nextFire` (Task 2).
- Produces: `abstract class AlarmRepository { Future<List<Alarm>> all(); Future<void> upsert(Alarm a); Future<void> softDelete(String id); Stream<List<Alarm>> watch(); }` — `upsert` tăng `rev` và đặt `updatedAt`, xóa là đặt `deleted = true`; `all()` không trả báo thức đã xóa.

- [ ] **Step 1: Test lỗi** `alarm_repository_test.dart` (SQLite in-memory): upsert rồi `all()` trả đúng; upsert hai lần tăng `rev` 1→2; `softDelete` ẩn khỏi `all()` nhưng bản ghi còn (để sync biết).
- [ ] **Step 2: Cài `AlarmRepository`** bằng SQLite cục bộ; chạy test PASS.
- [ ] **Step 3: Widget test** `alarm_edit_page_test.dart`: lưu với `target < start` hiện lỗi từ `validate` và không gọi `upsert`; dán link YouTube hợp lệ bật nút Lưu.
- [ ] **Step 4: Cài hai màn hình**: danh sách (bật/tắt nhanh, giờ kế tiếp từ `nextFire`, đầu ra loa) và soạn (đủ tham số ở spec mục 2.3/3, `CurvePreview` vẽ đường cong từ `volumeAt`).
- [ ] **Step 5: Commit** `feat(app): local storage and alarm list/edit UI`; chạy `deploy.sh`, xác nhận trên điện thoại tạo/sửa/xóa được.

### Task 4: Phát âm thanh có fade, báo thức chính xác, màn khóa, khởi động lại

**Files:**
- Create: `lib/audio/fade_player.dart`, `lib/audio/volume_guard.dart`, `lib/audio/output_route.dart`, `lib/alarm/scheduler.dart`, `lib/ui/ringing_page.dart`, `lib/ui/health_page.dart`
- Create (Kotlin): `android/app/src/main/kotlin/vn/aisolutions/video_timer_player/AlarmReceiver.kt`, `RingService.kt`, `BootReceiver.kt`, `AudioControl.kt` (MethodChannel `vtp/audio`)
- Modify: `android/app/src/main/AndroidManifest.xml`
- Test: `test/audio/fade_player_test.dart`, `test/alarm/scheduler_test.dart`

**Interfaces:**
- Consumes: `volumeAt`, `nextFire`, `Alarm`, `AlarmRepository` (Task 2, 3).
- Produces:
  - `class FadePlayer { Future<void> play(String filePath, VolumeSpec v, {Clock clock}); Future<void> stop(); Future<void> pauseForCall(); }` — mỗi tick (≈200 ms) đặt `player.volume = volumeAt(v, elapsed)`.
  - `class VolumeGuard { Future<void> lockSystemVolume(double level); Future<void> restore(); }` — lưu âm lượng cũ vào bộ nhớ bền (SharedPreferences) **trước** khi đổi, để khôi phục được cả khi tiến trình bị kill.
  - `enum OutputKind { speaker, bluetooth, wired, anyConnected }`; `Future<OutputState> currentOutput()`
  - `class AlarmScheduler { Future<void> rescheduleAll(); Future<void> onFired(String alarmId, {required DateTime scheduledFor, required DateTime now}); }`
  - Quy tắc `onFired`: nếu `now - scheduledFor` > 10 phút thì **không phát**, ghi nhận "lỡ" và hiện thông báo; ngược lại bắt đầu chuỗi phát.

- [ ] **Step 1: Test lỗi** `fade_player_test.dart` (đồng hồ giả + player giả): âm lượng đúng theo `volumeAt` tại các mốc; `stop()` đặt về 0 và gọi `VolumeGuard.restore`; ramp dài hơn hold vẫn dừng đúng ở hold.
- [ ] **Step 2: Test lỗi** `scheduler_test.dart`: `rescheduleAll` đặt đúng mốc `nextFire` cho mọi báo thức bật và hủy báo thức đã xóa/tắt; `onFired` với trễ 3 phút → phát, trễ 2 giờ → "lỡ", không phát.
- [ ] **Step 3: Cài `FadePlayer`, `VolumeGuard`, `AlarmScheduler`** (dùng `just_audio` với `AudioAttributes` usage media). Khi khởi động app/service, nếu `VolumeGuard` còn bản lưu từ lần chạy trước thì khôi phục ngay.
- [ ] **Step 4: Cài Kotlin**: `AlarmReceiver` nhận exact alarm (`setAlarmClock`), khởi chạy `RingService` (foreground, wake lock, full-screen intent tới `RingingPage`); `BootReceiver` gọi `rescheduleAll`; `AudioControl` đọc/đặt âm lượng STREAM_MUSIC và báo loại đầu ra. Khai báo quyền ở Global Constraints.
- [ ] **Step 5: `RingingPage`** (Dừng / Báo lại 5 và 10 phút / Nhỏ lại tạm 1 phút); báo lại bắt đầu lại từ âm khởi đầu. `HealthPage`: kiểm tra quyền, tối ưu pin, exact alarm, thông báo; nút mở đúng màn cài đặt.
- [ ] **Step 6: Đầu ra loa:** job ~10 phút trước giờ báo kiểm tra `currentOutput()`; thiếu loa mong muốn thì đẩy thông báo; lúc báo vẫn phát bằng loa trong; loa ngắt giữa chừng tự chuyển sang loa trong.
- [ ] **Step 7: Verify trên máy thật** (`deploy.sh`): báo thức 2 phút tới với file mẫu — màn khóa, fade đúng, Dừng/Báo lại chạy; khởi động lại máy trước giờ báo vẫn kêu; khởi động lại **sau** giờ báo → thông báo "lỡ", không kêu; kill app giữa lúc fade → âm lượng hệ thống được khôi phục. Commit.

### Task 5: Tải audio YouTube, cache và chuỗi dự phòng

**Files:**
- Create: `lib/audio/youtube_source.dart`, `lib/audio/audio_cache.dart`, `lib/audio/fallback_chain.dart`, `lib/alarm/prefetch_job.dart`, `assets/audio/default_ring.mp3`
- Test: `test/audio/youtube_source_test.dart`, `test/audio/fallback_chain_test.dart`

**Interfaces:**
- Consumes: `Alarm`, `FadePlayer` (Task 2, 4).
- Produces:
  - `abstract class AudioSource { Future<FetchResult> fetch(String url, {Duration? start, Duration? end}); }` với `FetchResult.ok(String path)` hoặc `FetchResult.failed(FetchError reason)`; `enum FetchError { invalidUrl, privateOrDeleted, ageRestricted, playlist, network, extractorBroken }`
  - `String? parseVideoId(String input)` hỗ trợ `watch?v=`, `youtu.be/`, `shorts/`, `m.youtube.com`, ID trần 11 ký tự; từ chối playlist-only
  - `class AudioCache { Future<String?> get(Alarm a); Future<void> put(Alarm a, String path); Future<bool> isHealthy(Alarm a); }` (kiểm tra file tồn tại, kích thước > 0, giải mã được)
  - `Future<String> resolvePlayable(Alarm a)` — thứ tự: cache khỏe → `fallbackPath` → `assets/audio/default_ring.mp3`; **không bao giờ ném lỗi**.

- [ ] **Step 1: Test lỗi** `parseVideoId`: các dạng link ở trên trả ID đúng; `playlist?list=` và chuỗi rác trả null.
- [ ] **Step 2: Test lỗi** `fallback_chain_test.dart`: cache hỏng + `fallbackPath` có → trả `fallbackPath`; cả hai thiếu → trả đường dẫn chuông có sẵn; nguồn ném mọi loại `FetchError` vẫn ra được đường dẫn phát được.
- [ ] **Step 3: Cài `parseVideoId`, `AudioCache`, `resolvePlayable`** (chạy test PASS), rồi `YoutubeAudioSource` bằng `youtube_explode_dart` (chọn luồng audio tốt nhất, tải xuống file, cắt đoạn nếu có). Mô-đun này chỉ lộ `AudioSource` để thay được.
- [ ] **Step 4: Tải khi lưu báo thức**, hiện tiến độ và lỗi bằng tiếng Việt đúng theo `FetchError`; lưu được kể cả khi tải lỗi (dùng dự phòng) nhưng cảnh báo rõ.
- [ ] **Step 5: `prefetch_job`** (WorkManager): đêm trước và ~10 phút trước giờ báo, nếu `isHealthy` sai thì tải lại; ghi kết quả vào `HealthPage`.
- [ ] **Step 6: Verify máy thật:** link thật → nghe được; tắt mạng rồi đặt báo thức → vẫn kêu bằng file đã tải; link riêng tư → lưu được, báo lỗi, kêu bằng dự phòng. Commit.

### Task 6: Các loại hẹn giờ và báo thức theo bậc

**Files:**
- Modify: `lib/core/schedule.dart`, `lib/alarm/scheduler.dart`, `lib/ui/alarm_edit_page.dart`, `lib/audio/fade_player.dart`
- Test: `test/alarm/staged_test.dart`, `test/alarm/countdown_test.dart`

**Interfaces:**
- Consumes: `ScheduleSpec` các biến thể, `FadePlayer`, `resolvePlayable`.
- Produces: `class Stage { Duration offset; String? youtubeUrl; VolumeSpec volume; }`; `FadePlayer.fadeOut(Duration d)` cho chế độ nhắc ngủ.

- [ ] **Step 1: Test lỗi** `staged_test.dart`: 3 mốc 06:00/06:20/06:30 → `nextFire` trả đúng mốc, mỗi mốc phát đúng bài và `VolumeSpec` riêng, không bắt đầu mốc sau khi người dùng đã Dừng cả chuỗi.
- [ ] **Step 2: Test lỗi** `countdown_test.dart`: đếm ngược 15 phút kêu đúng lúc kể cả sau khi app bị kill (dựa vào `startedAt` bền, không phụ thuộc bộ đếm trong RAM).
- [ ] **Step 3: Cài** Countdown, Windowed, Staged và `fadeOut`; thêm vào màn soạn. Chạy test PASS.
- [ ] **Step 4: Verify máy thật** từng loại với thời gian ngắn. Commit.

### Task 7: Web PHP + SQLite (máy chủ cấu hình)

**Files:**
- Create: `web/index.php`, `web/lib/db.php`, `web/lib/auth.php`, `web/lib/csrf.php`, `web/lib/validate.php`, `web/api/sync.php`, `web/api/alarms.php`, `web/api/report.php`, `web/admin/{login,alarms,edit,devices,logs}.php`, `web/schema.sql`, `web/config.example.php`, `web/.htaccess`, `web/bin/create_admin.php`
- Test: `web/tests/run.php`, `web/tests/sync_test.php`, `web/tests/security_test.php`

**Interfaces:**
- Produces (JSON, header `Authorization: Bearer <device_token>`):
  - `GET api/sync.php?since=<rev>` → `{"serverRev":N,"alarms":[Alarm...],}` gồm cả bản ghi `deleted:true`, `rev` toàn cục tăng đơn điệu.
  - `POST api/alarms.php` body `{alarm, baseRev}` → 200 `{alarm}` nếu `baseRev == rev hiện tại`; **409** `{current: alarm}` nếu lệch.
  - `POST api/report.php` body `{alarmId, firedAt, status: fired|missed|fallback|error, detail}` → 204.
  - JSON của `alarm` trùng `Alarm.toJson` (Task 2).
- Schema theo spec mục 10.6; đường dẫn gốc/DB đọc từ `config.local.php`.

- [ ] **Step 1: Viết `schema.sql`** + `db.php` mở PDO sqlite với `PRAGMA foreign_keys=ON`, WAL, prepared statements duy nhất.
- [ ] **Step 2: Test lỗi** `sync_test.php` (chạy bằng `php web/tests/run.php`, DB tạm): token đúng → 200; không/sai token → 401; `since` lọc đúng; xóa mềm trả `deleted:true`; `POST` với `baseRev` cũ → 409 và không ghi đè; payload > 64 KB → 413; JSON sai kiểu (giờ là chuỗi, ramp âm) → 422 với lý do.
- [ ] **Step 3: Test lỗi** `security_test.php`: đăng nhập sai 5 lần bị khóa tạm; form POST không CSRF token bị từ chối; chuỗi `'; DROP TABLE alarms;--` trong tên không phá DB; `alarm.name` chứa `<script>` được escape khi hiển thị; truy cập `.sqlite` trực tiếp không phục vụ được (kiểm tra `.htaccess`/vị trí).
- [ ] **Step 4: Cài** `auth.php` (`password_hash`, phiên `HttpOnly/Secure/SameSite=Lax`), `csrf.php`, `validate.php` (dùng chung luật với `validate` ở Task 2, viết lại bằng PHP và có test đối chiếu cùng bộ ví dụ), các endpoint và trang quản trị (responsive, không JS nặng). Trang thiết bị tạo/thu hồi token (chỉ hiện token một lần).
- [ ] **Step 5: `bin/create_admin.php <user>`** hỏi mật khẩu từ stdin, ghi băm; không có tài khoản mặc định.
- [ ] **Step 6: Chạy `php web/tests/run.php`** → tất cả PASS; thử tay bằng `php -S 127.0.0.1:8088 -t web`. Commit `feat(web): PHP+SQLite config server`.

### Task 8: Đồng bộ app ↔ web và ô "URL máy chủ"

**Files:**
- Create: `lib/sync/sync_client.dart`, `lib/sync/sync_job.dart`, `lib/ui/settings_page.dart`
- Modify: `lib/data/alarm_repository.dart`, `lib/alarm/scheduler.dart`, `lib/alarm/prefetch_job.dart`
- Test: `test/sync/sync_client_test.dart`

**Interfaces:**
- Consumes: API ở Task 7, `AlarmRepository`, `AlarmScheduler.rescheduleAll`, `AudioCache`.
- Produces: `class SyncClient { Future<SyncResult> sync(); }` — kéo `since=<serverRev lưu>`, đẩy các bản ghi cục bộ chưa gửi; gặp 409 thì **lấy bản server và báo người dùng**; sau khi có thay đổi gọi `rescheduleAll` và prefetch cho link mới. Cài đặt: `serverUrl`, `deviceToken`, "Kiểm tra kết nối", thời điểm sync gần nhất. `serverUrl` rỗng → `sync()` không làm gì và không lỗi.

- [ ] **Step 1: Test lỗi** `sync_client_test.dart` (server giả): kéo bản mới → ghi vào repo và gọi `rescheduleAll`; 409 → giữ bản server, trả `SyncResult.conflict`; mạng lỗi/timeout → không đổi dữ liệu cục bộ, trả `SyncResult.offline`, **không ném lỗi**; `serverUrl` rỗng → no-op; báo thức sắp kêu trong ≤ 15 phút bị đổi → `SyncResult.changedImminent` để UI báo người dùng.
- [ ] **Step 2: Cài `SyncClient`, `sync_job`** (WorkManager 15–30 phút + trước giờ báo ~10 phút + khi mở app), và gửi `report` sau mỗi lần báo thức chạy (kể cả "lỡ"/dự phòng) từ `AlarmScheduler.onFired`.
- [ ] **Step 3: `SettingsPage`** với ô URL, token, nút kiểm tra kết nối.
- [ ] **Step 4: Verify end-to-end:** chạy web local (`php -S 0.0.0.0:8088`), trỏ app tới địa chỉ LAN, sửa giờ trên web → app đổi báo thức sau lần sync; sửa trên app → web thấy; tắt web → báo thức vẫn kêu. Commit.

### Task 9: Triển khai web lên aisolutions.vn và nghiệm thu trên thiết bị

**Files:**
- Create: `docs/RUNBOOK.md`, `docs/ACCEPTANCE.md`, `scripts/deploy_web.sh`

**Interfaces:**
- Consumes: toàn bộ các task trước. Cần từ anh: cách truy cập hosting (SSH/SFTP/cPanel) hoặc anh tự upload.

- [ ] **Step 1: Hosting đã xác minh (2026-11-02, chỉ đọc) — SỬA so với bản trước:** `aisolutions.vn` chạy trên máy **Windows ASUS** (`TA@42.118.174.22:22`, SSH key của `javis-ai`, shell PowerShell; chi tiết `/home/javis-ai/TA/Projs/asus_info/README.md`), **không phải** máy Linux này (bản Linux cũ không còn phục vụ, không được deploy vào đó). XAMPP Apache + PHP có `pdo_sqlite`, `sqlite3`. DocumentRoot: `E:\21_Servers\01_web_php_aisolutions\https__cp1.step.com.vn_2083`; thư mục `alarm\` chưa tồn tại, công khai `/alarm/` đang 404. `.htaccess` gốc có rewrite riêng: không sửa, nếu cần rule thì đặt `.htaccess` trong `alarm\`. Ghi vào `RUNBOOK.md`.
- [ ] **Step 2: `scripts/deploy_web.sh`** chạy từ máy Linux: `tar --format=posix -cf - web | ssh -p 22 TA@42.118.174.22 "cmd /c tar -xf - -C <đích>"` (không có rsync; lệnh phức tạp thì ghi `.ps1`, `scp` sang rồi chạy `powershell -NoProfile -File`). Trước khi ghi phải `Test-Path` xác nhận `alarm\` chưa có hoặc chỉ chứa bản của dự án này; không đè `config.local.php`. **DB SQLite đặt ngoài DocumentRoot**, ví dụ `E:\21_Servers\data\alarm\` (cùng cấp `data\sach-y`), và cần kiểm tra quyền ghi của tài khoản chạy Apache. Sau mỗi lần deploy ghi một dòng vào `E:\21_Servers\HANDOFF.md` hoặc gửi tin vào `E:\21_Servers\messages\` theo `PROTOCOL.md`. Việc này chạm vào máy chủ đang phục vụ công khai nên **chỉ chạy sau khi anh Dương Thần xác nhận**, và nhắn agent `ASUS-web` nếu cần.
- [ ] **Step 3: Tạo tài khoản quản trị** bằng `bin/create_admin.php` trên máy chủ, ghép điện thoại bằng token.
- [ ] **Step 4: Nghiệm thu** theo `ACCEPTANCE.md`, mỗi mục có kết quả ghi lại: khóa màn hình, Doze qua đêm, tắt mạng, tắt/ngắt Bluetooth, khởi động lại máy, link lỗi, sửa từ web, web sập. Chỉ khi toàn bộ đạt mới coi là xong. Commit.

---

## Self-review (đã chạy)

- **Phủ spec:** mục 2.1 → T5; 2.2 → T4; 2.3 → T2/T4; 2.4 → T4; mục 3 → T6; mục 4 → T4; mục 5 → T3/T4; mục 6 → T1/T9; mục 10 → T7/T8/T9. Thiếu: hồ sơ ngày thường/cuối tuần chỉ qua `Weekly` (chấp nhận, ghi chú); "Nhắc ngủ" (fade-out) thuộc T6, ưu tiên thấp.
- **Nhất quán kiểu:** `Alarm`, `VolumeSpec`, `volumeAt`, `nextFire`, `resolvePlayable`, `AlarmScheduler.onFired` dùng cùng tên ở mọi task.
- **Chưa chốt (người làm quyết, theo spec mục 8):** `drift` hay `sqflite`; thư viện alarm native hay tự viết Kotlin (kế hoạch dùng Kotlin tự viết để kiểm soát fade/foreground service); web ở `web/` cùng repo.
- **Tỷ lệ:** kế hoạch chỉ chứa chữ ký, test và giá trị chốt; không chứa thân hàm.
