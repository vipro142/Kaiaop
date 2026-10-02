# LIVEPRO 3.2 — Phòng động, tên sự kiện và mật khẩu

Dashboard: https://116.118.45.184:6004/ . Đăng nhập bằng tài khoản quản trị hiện tại.

## Thêm/xóa phòng
Bấm Thêm phòng, nhập tên, bấm Tạo phòng. Không giới hạn cứng số phòng trong phần mềm; năng lực VPS và mạng vẫn giới hạn tải thực tế. Phòng mới mặc định mở, 30 thiết bị. Bấm Quản lý / Devices để đổi tên, giới hạn, lịch, mật khẩu hoặc xóa phòng. Xóa phòng sẽ kick mọi thành viên và dừng ADMIN giám sát trong phòng đó. Phòng khác không bị ảnh hưởng. Có thể xóa hết rồi tạo lại.
Mã phòng được tạo tự động và giữ nguyên khi đổi tên, giúp Tally không đổi địa chỉ. Phòng xóa rồi tạo lại là phòng mới với mã mới. Tên từ 1–60 ký tự. Tên đang ở trong phòng cập nhật ngay; danh sách chọn phòng cập nhật khoảng 2 giây khi có mạng.

## Mật khẩu sự kiện
Trong Quản lý / Devices: chọn Yêu cầu mật khẩu, nhập mật khẩu mới từ 4–128 ký tự và lưu. Muốn đổi mật khẩu thì nhập mới rồi lưu; để trống giữ mật khẩu hiện tại. Chọn Không khóa để bỏ yêu cầu mật khẩu, không cần xóa mật khẩu cũ. Không hiển thị lại mật khẩu đã lưu; có thể đặt mới nếu quên.
Điện thoại, Windows, iOS chỉ hiện ô nhập mật khẩu cho phòng khóa. Không lưu mật khẩu phòng vào cài đặt trên thiết bị. Đổi mật khẩu không kick người đang ở trong phòng; rời phòng hoặc kết nối lại phải xác thực mật khẩu hiện tại. Bộ đàm được miễn mật khẩu theo loại app radio. Miễn khóa dựa trên nhận diện app gửi lên, không phải xác thực phần cứng chống giả mạo. ADMIN đăng nhập dashboard không cần nhập lại mật khẩu phòng.
Mật khẩu lưu dạng scrypt trên server, không có trong API danh sách phòng, thông báo đồng bộ hay nhật ký. Dashboard dùng HTTPS. Giao thức TCP/UDP của các app vẫn như hệ thống hiện có, chưa mã hóa TLS; mật khẩu phòng là kiểm soát tham gia, không phải mã hóa cuộc gọi. Không dùng lại mật khẩu tài khoản quan trọng làm mật khẩu phòng.

## Cài đồng bộ
Cài Radio 3.2 cho bộ đàm, Android Phone 3.2 cho điện thoại, Windows 3.2.0 portable. iOS 3.2 là mã nguồn Xcode cần Mac để biên dịch và ký, chưa có IPA. App 3.0/3.1 không có đủ chức năng phòng động/mật khẩu, cần nâng cấp lên 3.2; các app trước 3.0 vẫn bị từ chối giao thức.

## Kiểm tra
Server kiểm thử mật khẩu đúng/sai/đổi/tắt, radio miễn khóa, không kick khi đổi, không lộ mật khẩu trong dữ liệu phản hồi; tạo/xóa hết/tạo lại phòng; giới hạn, lịch, kick và ADMIN. Dashboard và Windows kiểm thử đồng bộ danh sách và ô mật khẩu qua trình duyệt. Đã thử phòng tạm có mật khẩu trên VPS và Windows đăng ký/UDP thành công rồi xóa phòng tạm. Android 25 kiểm thử điện thoại và 21 kiểm thử bộ đàm, build/lint thành công. Chưa thử âm thanh thực tế trên thiết bị của bạn; iOS chỉ kiểm tra cú pháp trên Windows.

## Sao lưu
VPS: /opt/projects/intercom-server/management-state.json chứa cấu hình, lịch, tên, mật khẩu băm và tài khoản, cần sao lưu riêng. Nguồn ZIP không chứa state hay chứng chỉ/mật khẩu. Bản sao trước cập nhật tại /opt/projects/intercom-server-backup-before-rooms32.
