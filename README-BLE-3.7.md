# LivePro 3.8.1 — Tally Bluetooth

Android dien thoai va bo dam dung cung giao dien Search/Stop, danh sach Tally..., va trang thai ben duoi. iOS duoc sua dong bo trong goi nguon Xcode 3.8.1 build50, chua co IPA vi chua co Mac.

Bo dam: nut Tally Bluetooth co highlight khi focus. Trong hop thoai Tally, xoay dial (DPAD UP/DOWN hoac LEFT/RIGHT) de di lan luot Search -> Stop -> cac dong Tally -> Dong; bam dial/ENTER de chon. Focus quay vong va cuon theo dong duoc chon.

Tally dang ket noi ngung quang ba Bluetooth. Search van giu dong tally dang dung voi nhan Da ket noi; cac tally khac hien khi do duoc. Khong gioi han 1-8. Dong dang ket noi la lien ket hien tai, khong phai mot thiet bi moi vua quet duoc.

Firmware ESP32 2.1 giu nguyen, tuong thich 3.8.1. Lien ket cu duoc giu qua cap nhat app; Stop khi dang ket noi giai phong tally. RST giu lien ket; BOOT giu3 giay khi mach dang chay de xoa lien ket. Stop khi ESP khong reachable chi xoa lua chon app; reset tren ESP de giai phong chu so huu cu.

Android co dich vu Standby va khoi phuc sau boot. iOS can LivePro duoc mo/duoc he dieu han khoi phuc; khong dam bao tu chay sau cold boot/force-quit. Swift syntax va plist duoc kiem tra tren Windows, chua build/type-check Xcode hay test iPhone. Mo LivePro.xcodeproj tren Mac de ky va build.

Arduino: goi LiveProTally-Arduino-2.1.zip. Doi TALLY_NUMBER trong .ino de dat Tally9/Tally12/...; GPIO4 do, GPIO5 xanh, GND am chung, moi mau qua dien tro330 ohm. Dung ESP32 core2.0.17, NimBLE-Arduino2.3.7, ESP32C3 Dev Module, USB CDC On Boot Enabled,4MB DIO40MHz.
