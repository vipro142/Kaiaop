# LIVEPRO Intercom iOS — bàn giao mã nguồn 1.0

## Trạng thái
Đây là dự án Xcode cho iPhone/iPad iOS 15 trở lên, chưa phải ứng dụng đã biên dịch. Trên Windows đã kiểm tra cú pháp Swift bằng tree-sitter, XML Info.plist/scheme và tài nguyên. Chưa chạy Xcode, XCTest, Simulator hoặc kiểm tra âm thanh thiết bị thật. Cần biên dịch trên Mac trước khi ký/cài; không chỉ ký ZIP này.

## Chức năng đã viết
Giao diện LIVEPRO màu tối, bố cục iPhone/iPad; tên bắt buộc; sự kiện A–J; sáu vai trò; thiết bị 1–30 dùng chung số trong mỗi sự kiện; camera riêng 1–30 và cảnh báo trùng 1,5 giây; danh sách Devices/người đang nói; Tally toàn màn hình; bộ đếm lưu lượng. Kết nối cùng máy chủ Android/Windows tại 116.118.45.184, TCP 6000 và UDP 6001. Nói đa chiều không ưu tiên đạo diễn. Đạo diễn có bật/tắt mic hoặc PTT, vai trò khác giữ PTT.

Âm thanh dùng AVAudioEngine Voice Processing, PCM 16 kHz mono để tương thích máy chủ. Hiệu quả khử vọng giữa nhiều máy ở gần nhau cần thử thực tế. Menu loa có Loa ngoài, Loa thoại, Loa ON và Loa OFF; iPad không có loa thoại như iPhone, đường phát tùy thiết bị. Có bộ chọn thiết bị âm thanh hệ thống.

## Chạy nền
Đã cấu hình UIBackgroundModes=audio và AVAudioSession playAndRecord/voiceChat. Khi đang trong phòng, chuyển app/khóa màn hình giữ engine và kết nối. Đạo diễn bật mic bằng nút bật/tắt trước khi ẩn app thì mic giữ hoạt động. PTT giữ tay nhả khi app mất trạng thái active; các vai trò PTT vẫn nghe nền, muốn nói thì mở app giữ PTT. Không tự bật mic mới khi ứng dụng đang nền.

Vuốt đóng hẳn/force quit sẽ chấm dứt phiên. Cuộc gọi hoặc thay đổi thiết bị âm thanh sẽ dừng mic; mở lại app kiểm tra kết nối và bật mic lại. Hành vi nền còn phải kiểm chứng trên iPhone/iPad thật; không cam kết duy trì khi hệ thống chấm dứt tiến trình.

## Mở trên Mac và cài thử
1. Giải nén ZIP, mở LivePro.xcodeproj bằng Xcode.
2. Chọn target LivePro → Signing & Capabilities → Automatically manage signing → chọn Team. Đăng nhập Apple Account trong Xcode nếu chưa có. Có thể dùng Personal Team để cài thử trên thiết bị cá nhân; không cần mua membership chỉ để thử.
3. Đổi Bundle Identifier nếu tài khoản yêu cầu mã riêng, ví dụ com.tenban.livepro.intercom.
4. Cắm iPhone/iPad, chọn thiết bị trong Xcode rồi Product → Run. Chấp nhận quyền microphone; bật Developer Mode trên thiết bị nếu Xcode yêu cầu.
5. Để tạo gói chưa ký: mở Terminal tại thư mục dự án, chạy `bash build-unsigned.command`. Chỉ khi build thành công mới có `build/LIVEPRO-Intercom-unsigned.ipa`. Gói này vẫn cần chứng chỉ/provisioning phù hợp trước khi cài.

Dự án dùng định dạng Xcode 14 và Swift 5, không có thư viện ngoài. Xcode 14.2 yêu cầu Monterey 12.5 trở lên, phù hợp để cân nhắc trên Mac cũ; khả năng kết nối thiết bị phụ thuộc phiên bản iOS/Xcode. Nếu iPhone dùng iOS mới hơn phạm vi Xcode hỗ trợ thì cần môi trường Xcode mới tương ứng, không đảm bảo MacBook Air 2017 đáp ứng.

## Kiểm tra trên Mac
Product → Test chạy sáu ca XCTest: JSON bị chia gói/nhiều gói, dữ liệu lỗi/quá lớn, chia frame PCM, hồ sơ/định danh, danh sách thành viên và chính sách mic nền. Chưa thực thi các ca này trên Windows.

Kiểm tra thực tế với Android/Windows cùng sự kiện: nghe/nói hai chiều và đồng thời; kiểm tra mic tự gửi về không bị lặp; đổi loa/tai nghe; kiểm tra camera trùng và số thiết bị; bật mic đạo diễn rồi khóa màn hình/chuyển app ít nhất 5 phút; giữ PTT rồi chuyển app phải dừng gửi; mất mạng/khôi phục; có cuộc gọi chen vào; rời phòng phải dừng âm thanh. Thử cả iPhone màn hình nhỏ và iPad ngang.

## Tài liệu Apple
- Xcode: https://developer.apple.com/xcode/system-requirements
- Tài khoản/cài thử: https://developer.apple.com/help/account/basics/about-your-developer-account
- Audio nền: https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord
- Voice processing: https://developer.apple.com/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled(_:)
