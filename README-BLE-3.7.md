# LivePro 3.8.2 / ESP32 firmware 2.2

Search hien tat ca Tally... co dich vu LivePro, bao gom tally da duoc chon. Firmware2.2 van quang ba Bluetooth khi dang ket noi; luc nay tally khong nhan ket noi thu hai. App hien nhan Da duoc chon/Da ket noi. Bam bat ky tally da duoc chon (ke ca tally cua chinh app) se hien popup: Tally nay da duoc chon. Hay chon tally khac hoac giu nut BOOT tren tally3 giay de reset lien ket va pair lai.

Tally giu owner qua mat ket noi/khoi dong lai. App chu cu van tu noi lai khi tally available. Stop khi dang noi xoa owner; BOOT giu3 giay khi mach dang chay xoa owner. RST chi reboot va giu owner. Sau reset, app cu khong duoc tu chiem lai: phai chon thu cong. Stop khi ESP khong reachable chi xoa lua chon trong app, can reset ESP de giai phong owner cu.

Bo dam: highlight vang khi focus; dial UP/DOWN/LEFT/RIGHT di Search -> Stop -> danh sach -> Dong, bam dial/ENTER de chon. Popup co nut OK co the bam bang dial.

Android dien thoai va bo dam deu3.8.2. iOS3.8.2 build51 la nguon Xcode, da kiem tra syntax/plist nhung chua compile/type-check Xcode hay test iPhone. Can Mac va signing de tao IPA. iOS can LivePro duoc mo/duoc he dieu han khoi phuc; khong dam bao tu chay sau cold boot/force-quit. Android co foreground service Standby va khoi phuc sau boot neu app chua bi force-stop.

Arduino: mo LiveProTally/LiveProTally.ino va doi TALLY_NUMBER, khong gioi han1-8. ESP32 core2.0.17, NimBLE-Arduino2.3.7, ESP32C3 Dev Module, USB CDC On Boot Enabled, flash4MB DIO40MHz. LED am chung GND, doGPIO4, xanhGPIO5, moi mau qua dien tro330 ohm. 0OFF/1PROGRAM do/2PREVIEW xanh; watchdog5 giay tat den.

Manufacturer protocol prototype IDFFFF: LP, version1, flags bit0 owner persisted, bit1 active central. Lua chon chi doc trang thai quang ba; firmware van xac thuc HMAC va owner token. Khoa nam trong app/source, khong phai bao ve tuyet doi truoc reverse engineering. Quang ba khong chua owner token hay nonce.
