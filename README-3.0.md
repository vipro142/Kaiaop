# LIVEPRO 3.0 — Dashboard và ứng dụng đồng bộ

Dashboard: https://116.118.45.184:6004/ (cổng 6003 chuyển hướng HTTPS).
Tài khoản ban đầu: admin / admin123. Đổi mật khẩu trong mục Tài khoản.

## Điều hành
- Phòng A–J mặc định mở, mỗi phòng 30 thiết bị. Giới hạn chỉnh từ 1–300; đây là giới hạn phần mềm, chưa phải kết quả thử tải 300 người nói đồng thời.
- Giảm giới hạn giữ người đang kết nối, không nhận người vào lại khi số đang kết nối vẫn bằng/vượt giới hạn. Số thiết bị cũ cao hơn giới hạn vẫn giữ đến khi rời.
- Tắt phòng đưa mọi thiết bị về màn chờ; không tự vào lại. Kick từng thiết bị đưa về màn chờ; không phải lệnh cấm vĩnh viễn, họ có thể chủ động tham gia lại nếu phòng còn mở và còn chỗ.
- Đặt lịch một lần mở/đóng bằng dd/mm/yyyy HH:mm:ss hoặc dd/mm/yyyy HH,mm,ss, giờ Việt Nam UTC+7. Để trống để xóa lịch. Cấu hình được lưu trên VPS; lịch đến hạn khi server tắt sẽ được xử lý sau khi server khởi động.
- Admin chọn Quản lý / Devices → Vào nghe; Bật mic để nói, Tắt mic để dừng. Người trong phòng nhìn thấy ADMIN đang giám sát, ADMIN khi nói có màu nổi bật. Admin không chiếm số thiết bị và không nằm trong Devices của app.
- Tài khoản con được quản lý phòng, kick và nghe/nói; chỉ admin chính được tạo/xóa tài khoản. Xóa tài khoản hoặc đổi mật khẩu thu hồi phiên đăng nhập và giám sát. Không ghi âm cuộc trò chuyện.
- Máy chủ hiển thị uptime, RAM tiến trình, tải hệ thống, số kết nối, tổng byte âm thanh, nhật ký thao tác; không phải trình quản lý mọi dịch vụ VPS.

## Bắt buộc cập nhật
Máy chủ chỉ nhận giao thức 4. Các app trước 3.0 không thể dùng server này nữa.
Cài Android Phone 3.0 trên điện thoại; Radio 3.0 trên bộ đàm; chạy Windows 3.0.0 portable. Giữ các chức năng nền đã có. Radio không nhập tên, PTT cứng; đạo diễn bấm bật/tắt hoặc chọn PTT giữ tay. Camera vẫn chọn số 1–30, độc lập với giới hạn số thiết bị.

iOS 3.0 bàn giao dự án Xcode có cùng giao thức, nhận kick/đóng phòng, giới hạn mới và ADMIN. Chưa có IPA: Windows không có Xcode, chưa biên dịch hoặc thử trên iPhone. Xem README-VI trong ZIP để build trên Mac.

## Xác minh
Android đàm/điện thoại build thành công, unit tests gồm số thiết bị >30, ADMIN hiển thị/không có trong Devices, kick về màn chờ. Lint không lỗi build. Windows 4 kiểm thử audio/transport đạt. Server đã thử đăng nhập, chặn bản cũ, giới hạn mềm, kick, lịch, tài khoản/quyền/thu hồi, dữ liệu audio ADMIN hai chiều. Dashboard thử desktop/mobile, sửa giới hạn và thử HTTPS/mic giả lập trên trình duyệt kết nối VPS. Chưa thử âm thanh thực tế trên phần cứng của bạn hoặc thử tải tối đa.

## Vận hành VPS
Service: intercom-server. Thư mục /opt/projects/intercom-server.
State lưu trong management-state.json (mật khẩu scrypt), cần sao lưu cùng server; không có trong ZIP bàn giao. Khởi động lại server ngắt phiên và đăng nhập dashboard.
Chứng chỉ Let's Encrypt IP, tự gia hạn bằng livepro-cert-renew.timer hai lần mỗi ngày; server đọc lại chứng chỉ mỗi giờ. Cổng 80 cần tiếp tục phục vụ /.well-known/acme-challenge/ để gia hạn. 6005 chưa sử dụng.
Bản sao trước nâng cấp: /opt/projects/intercom-server-backup-before-v3. Nếu rollback phải gỡ cấu hình systemd dashboard.conf và khôi phục server cũ; các chức năng quản trị mới sẽ không còn.
