import 'package:flutter/material.dart';

/// Step by step: where to find the details this app needs, for someone who uses the Tuya app.
class TuyaGuidePage extends StatelessWidget {
  const TuyaGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget h(String s) => Padding(padding: const EdgeInsets.only(top: 20, bottom: 6), child: Text(s, style: text.titleMedium));
    Widget p(String s) => Padding(padding: const EdgeInsets.only(bottom: 6), child: SelectableText(s));
    return Scaffold(
      appBar: AppBar(title: const Text('Hướng dẫn kết nối Tuya')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        p('App này điều khiển ổ cắm trực tiếp qua wifi nhà (không qua internet), nên cần 3 thông tin của ổ cắm: Device ID, địa chỉ IP và Local key. '
            'Hai thông tin đầu xem được ngay trong app Tuya; Local key thì Tuya không hiện trong app, phải lấy một lần ở trang nhà phát triển.'),
        h('Bước 1. Thêm ổ cắm vào app Tuya'),
        p('Làm như bình thường: mở app Tuya trên điện thoại, bấm "+", thêm ổ cắm, đặt tên. Điện thoại và ổ cắm phải dùng cùng một wifi 2.4 GHz.'),
        h('Bước 2. Xem Device ID và IP trong app Tuya'),
        p('Mở ổ cắm trong app → bấm biểu tượng bút chì hoặc ba chấm ở góc trên bên phải → "Thông tin thiết bị" (Device Information). '
            'Ở đó có "ID thiết bị" (Virtual ID / Device ID) và "Địa chỉ IP". Tên mục có thể khác đôi chút tùy phiên bản app.'),
        p('Nếu không thấy IP: vào trang quản trị router, xem danh sách thiết bị đang kết nối, tìm ổ cắm (tên thường có chữ "Tuya", "ESP" hoặc "Smart"). '
            'Nên đặt IP cố định (DHCP reservation) cho ổ cắm để IP không đổi.'),
        h('Bước 3. Lấy Local key (làm một lần)'),
        p('Cách A: dùng trình duyệt, không cần cài gì'),
        p('1. Vào iot.tuya.com, đăng ký tài khoản nhà phát triển (miễn phí).\n'
            '2. Cloud → Development → Create Cloud Project. Chọn trung tâm dữ liệu (Data Center) khớp với khu vực tài khoản app Tuya của anh '
            '(trong app: Tôi → Cài đặt → Tài khoản và bảo mật → Khu vực).\n'
            '3. Trong project: Devices → Link App Account → Add App Account, rồi dùng app Tuya quét mã QR hiện ra để liên kết.\n'
            '4. Cũng trong project, vào mục Service API, đăng ký (subscribe) dịch vụ "IoT Core" (gói dùng thử miễn phí).\n'
            '5. Cloud → API Explorer → Device Management → "Query Device Details", nhập Device ID của ổ cắm, bấm Submit. '
            'Kết quả JSON có trường "local_key": đó là Local key (16 ký tự).'),
        p('Cách B: dùng máy tính có Python. Cài công cụ TinyTuya rồi chạy "python -m tinytuya wizard" (nhập Access ID và Secret của project ở bước 2). '
            'Công cụ in ra Device ID, Local key và cả IP của mọi thiết bị trong tài khoản; "python -m tinytuya scan" quét mạng tìm IP và phiên bản giao thức.'),
        h('Bước 4. Nhập vào app này'),
        p('Quay lại màn hình Tuya → "Thêm thiết bị" → nhập tên, Device ID, IP, Local key. Phiên bản giao thức chọn 3.3 trước. '
            'Bấm "Thử BẬT": ổ cắm phải kêu tách và bật. Không được thì thử 3.4.'),
        h('Lưu ý'),
        p('• Ổ cắm chỉ nhận một kết nối tại một lúc: nếu thử mà báo hết thời gian, hãy đóng hẳn app Tuya (vuốt tắt) rồi thử lại.\n'
            '• Local key đổi nếu anh xóa ổ cắm khỏi app Tuya và thêm lại (hoặc reset ổ cắm). Khi đó phải lấy key mới.\n'
            '• Điện thoại phải ở cùng wifi với ổ cắm lúc hẹn giờ chạy. Ra khỏi nhà thì hẹn giờ không điều khiển được.\n'
            '• Một số ổ cắm đời mới dùng giao thức 3.5, app này chưa hỗ trợ.\n'
            '• Local key là mật khẩu của ổ cắm: đừng gửi cho người khác.'),
      ]),
    );
  }
}
