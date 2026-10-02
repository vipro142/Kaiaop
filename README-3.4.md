# LIVEPRO 3.4 — Đồng bộ Tally, OSEE và nút tai nghe

## Tally select Windows ↔ dashboard
- Chọn Default/Kai trên Windows cập nhật cấu hình phòng trên VPS. Dashboard và các máy Windows cùng phòng nhận thay đổi.
- Chọn nguồn trên dashboard cập nhật Windows trong phòng. Dashboard đang mở tự làm mới sau tối đa khoảng 2 giây; nếu đang sửa chưa lưu, bản nháp không bị ghi đè.
- Không cần chọn Kai trên dashboard trước khi liên kết tài khoản trong Windows.
- Đăng nhập Kai thất bại hoặc thiếu tài khoản: phòng về Default, cả hai giao diện hiển thị nguồn thực tế. Ô đăng nhập trên Windows còn hiện để bạn sửa thông tin và thử lại.
- Default cần nguồn vMix/bridge hoạt động mới có tín hiệu đèn. Chuyển nguồn không tự tạo ra tín hiệu khi không có nguồn phần cứng.
- Nếu bridge đang chạy và nguồn phòng đổi, Windows chuyển bridge theo nguồn mới và cấu hình đã lưu.
- Mỗi phòng độc lập. Các phòng cùng tài khoản Kai sẽ cùng dùng bảng đèn của tài khoản đó.

## OSEE GoStream
Trong Kai Tally → Signal Source → OSEE GoStream.
Nhập IP bàn OSEE (mặc định 192.168.10.240) và cổng nhận UDP (54321). Để trống IP nếu muốn nhận từ mọi nguồn.
Bàn OSEE cần gửi UDP tới IP máy Windows và đúng cổng đó; cho phép app nhận UDP qua firewall khi Windows hỏi.
Đã khôi phục logic nhánh OSEE cũ: gói 12 byte, PGM byte 11/PVW byte 10, mã camera 1–4, ánh xạ ra Tally, lọc IP, bỏ gói không hợp lệ, mất tín hiệu 1,5 giây thì tắt đèn.
Đã kiểm thử bằng gói UDP mô phỏng. Chưa thử trên bàn OSEE vật lý của bạn.

## Android điện thoại — nút tai nghe
Cài LIVEPRO-Intercom-3.4-Android-Phone.apk, tham gia phòng rồi bấm nút media/Play-Pause trên tai nghe.
Mặc định: bấm bật mic, bấm lại tắt mic. Áp dụng cả các vai trò PTT khi điều khiển bằng tai nghe; nút PTT trên màn hình vẫn giữ cơ chế cũ.
Trong nút loa → dòng Nút tai nghe, đổi sang Giữ để nói nếu tai nghe gửi được đủ ACTION_DOWN/ACTION_UP. Thả nút tắt mic; chế độ giữ có giới hạn an toàn 120 giây nếu mất sự kiện thả.
Tai nghe Bluetooth thường chỉ gửi một lệnh bấm, vì vậy nên dùng mặc định bật/tắt. Nút âm lượng, nút gọi trợ lý hoặc nút gọi điện do hệ điều hành giữ quyền không được ánh xạ lại.
MediaSession chỉ hoạt động khi đã vào phòng; không tự mở app hoặc tự vào phòng từ tai nghe. Điều khiển tai nghe được nhận khi app đang giữ phiên nền. Rút/ngắt tai nghe sẽ hủy nguồn mic từ tai nghe.
Đã build APK, lint và 28 bài kiểm thử thành công, gồm nhấn/thả, lệnh bấm chỉ có DOWN, chống sự kiện trùng và đóng phiên. Chưa kiểm thử bằng tai nghe vật lý, nên mức hỗ trợ phụ thuộc firmware tai nghe/điện thoại.

## iOS / iPadOS / AirPods
Mã nguồn 3.4 bổ sung MPRemoteCommandCenter: Play mở mic, Pause/Stop tắt mic, Toggle bật/tắt. Hoạt động khi hệ thống gửi lệnh media cho LIVEPRO đang trong phòng. Cập nhật trạng thái điều khiển và tắt quyền điều khiển khi rời phòng.
Không có API nhấn xuống/thả ra chung cho mọi tai nghe trên iOS. Không cam kết nhấn giữ PTT trên AirPods; chế độ dự kiến là bấm bật/tắt. Siri, chống ồn, thao tác mute cuộc gọi do hệ thống quản lý có thể không đi qua lệnh media của app.
Đã kiểm tra cú pháp Swift trên Windows, chưa biên dịch bằng Xcode/chưa thử iPhone/AirPods thật. File giao là mã nguồn Xcode, không phải IPA; cần Mac để biên dịch và ký.

## Các thiết bị còn lại
Bộ đàm giữ bản 3.2 và nút PTT vật lý hiện tại; vẫn nhận nguồn Tally đã đổi trên server. Android/iOS/bộ đàm nhận đèn theo phòng + số camera, không theo số thiết bị.

Tài liệu nền tảng tham khảo:
- Android media buttons: https://developer.android.com/media/legacy/media-buttons
- Apple MPRemoteCommand: https://developer.apple.com/documentation/mediaplayer/mpremotecommand
- AirPods controls: https://support.apple.com/en-au/guide/airpods/devb2c431317/web
