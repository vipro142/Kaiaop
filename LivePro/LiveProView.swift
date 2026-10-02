import SwiftUI
import UIKit
import AVKit

private let ink = Color(red: 0.043, green: 0.071, blue: 0.125)
private let panel = Color(red: 0.078, green: 0.125, blue: 0.192)
private let accent = Color(red: 0.47, green: 0.75, blue: 1)
private let muted = Color(red: 0.57, green: 0.66, blue: 0.77)

struct LiveProView: View {
    @ObservedObject var model: IntercomModel
    @State private var showDevices = false
    @State private var showGPS = false
    @StateObject private var gps = GPSTracker()
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var background: Color {
        model.tally == "program" ? Color(red: 0.72, green: 0.07, blue: 0.17)
        : model.tally == "preview" ? Color(red: 0.03, green: 0.43, blue: 0.20) : ink
    }
    var body: some View {
        ZStack(alignment: .bottom) {
            background.ignoresSafeArea()
            VStack(spacing: 0) {
                header.padding(.horizontal, 22).padding(.vertical, 16)
                if model.inRoom {
                    room.overlay(alignment: .topTrailing) {
                        if showGPS && model.profile.role == .camera && gps.choice > 0 {
                            gpsStatusPanel.frame(maxWidth: 320)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.5), lineWidth: 1))
                                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                                .padding(.horizontal, 16).padding(.top, 4)
                                .accessibilityIdentifier("gpsPopup")
                        }
                    }
                } else { setup }
            }
            if let notice = model.notice {
                Text(notice).font(.subheadline).multilineTextAlignment(.center)
                    .padding(16).frame(maxWidth: 540)
                    .background(Color(red: 0.16, green: 0.24, blue: 0.34))
                    .clipShape(RoundedRectangle(cornerRadius: 14)).padding(20)
                    .accessibilityLabel(notice)
                    .onTapGesture { model.dismissNotice() }
                    .accessibilityAddTraits(.isButton)
            }
        }
        .sheet(isPresented: $showDevices) { devicesSheet }
        .onChange(of: model.inRoom) { joined in if !joined { showDevices = false; showGPS = false } }
        .onAppear { gps.configure(camera: model.profile.role == .camera) }
        .onChange(of: gps.choice) { _ in showGPS = false; gps.configure(camera: model.profile.role == .camera) }
        .onChange(of: model.profile.role) { _ in showGPS = false; gps.configure(camera: model.profile.role == .camera) }
        .tint(accent)
    }
    private var header: some View {
        HStack(spacing: 14) {
            Text("L").font(.system(size: 25, weight: .black)).foregroundColor(ink)
                .frame(width: 42, height: 42).background(accent).cornerRadius(12)
            VStack(alignment: .leading, spacing: 4) {
                Text("LIVEPRO").font(.system(size: 18, weight: .bold, design: .rounded)).tracking(2)
                Text(model.connectionText).font(.caption2).foregroundColor(model.connected ? accent : muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            if model.inRoom {
                if model.profile.role == .camera && gps.choice > 0 {
                    Button { showGPS.toggle() } label: {
                        Text("GPS").font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 12)
                            .background(showGPS ? accent.opacity(0.25) : panel).cornerRadius(11)
                    }.accessibilityLabel(showGPS ? "Đóng thông tin GPS" : "Mở thông tin GPS")
                        .accessibilityIdentifier("gpsToggle")
                }
                Button { showGPS = false; showDevices = true } label: {
                    HStack(spacing: 6) { Image(systemName: "person.2"); Text("\(model.members.count)") }
                        .font(.subheadline.bold()).padding(12).background(panel).cornerRadius(11)
                }.accessibilityLabel("Devices: \(model.members.count) thiết bị")
            }
        }
    }
    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 9) {
                    eyebrow("CREW COMMUNICATION")
                    Text("Quản Lý Kênh\nLiên Lạc").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Một kênh liên lạc. Cả đội đồng bộ.").font(.subheadline).foregroundColor(muted)
                }
                VStack(alignment: .leading, spacing: 18) {
                    eyebrow("THAM GIA SỰ KIỆN")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TÊN CỦA BẠN *").font(.caption.bold()).foregroundColor(muted)
                        TextField("Nhập tên của bạn", text: $model.profile.name)
                            .textContentType(.name).submitLabel(.done).padding(13).background(ink).cornerRadius(10)
                            .accessibilityIdentifier("name")
                    }
                    selection("SỰ KIỆN") {
                        Picker("Sự kiện", selection: $model.profile.room) {
                            ForEach(model.roomIDs, id: \.self) { Text(model.roomTitle($0)).tag($0) }
                        }.onChange(of: model.profile.room) { _ in model.selectionChanged() }
                    }
                    selection("VAI TRÒ") {
                        Picker("Vai trò", selection: $model.profile.role) {
                            ForEach(CrewRole.allCases.filter { $0 != .admin }) { Text($0.title).tag($0) }
                        }.onChange(of: model.profile.role) { _ in model.selectionChanged() }
                    }
                    selection("SỐ THIẾT BỊ") {
                        Picker("Số thiết bị", selection: Binding(get: { model.profile.number }, set: { model.profile.number = $0; model.selectionChanged() })) {
                            if !model.freeNumbers.contains(model.profile.number) { Text("Chờ số trống").tag(model.profile.number) }
                            ForEach(model.freeNumbers, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                    }
                    selection("CAMERA SỐ") {
                        Picker("Camera số", selection: $model.profile.cameraNumber) {
                            ForEach(1...30, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }.disabled(model.profile.role != .camera)
                            .opacity(model.profile.role == .camera ? 1 : 0.35)
                            .onChange(of: model.profile.cameraNumber) { _ in model.selectionChanged() }
                    }
                    if model.profile.role == .camera {
                    selection("GPS CAMERA") {
                        Picker("Thiết bị GPS", selection: $gps.choice) {
                            ForEach(0..<GPSTracker.labels.count, id: \.self) { Text(GPSTracker.labels[$0]).tag($0) }
                        }.disabled(model.profile.role != .camera)
                    }
                    if gps.choice > 0 { gpsStatusPanel }
                    if gps.choice > 0 && model.profile.role == .camera {
                        Button("Cho phép GPS luôn hoạt động") { gps.requestBackgroundPermission() }.font(.caption)
                    }
                    }
                    if model.passwordRequired {
                        SecureField("Mật khẩu sự kiện", text: $model.roomPassword).padding(13).background(ink).cornerRadius(10)
                    }
                    Text(model.availabilityText).font(.caption).foregroundColor(muted)
                    Button { model.join() } label: {
                        HStack { Text(model.joining ? "Đang mở âm thanh…" : "Tham gia kênh"); Spacer(); Image(systemName: "arrow.up.right") }
                            .font(.headline).foregroundColor(ink).padding(16).background(accent).cornerRadius(12)
                    }.disabled((!model.canJoin && !model.roomClosed) || model.joining).opacity(model.canJoin || model.roomClosed ? 1 : 0.45)
                        .accessibilityIdentifier("join")
                    Text("Số thiết bị duy nhất trong sự kiện · Giới hạn theo phòng").font(.caption2).foregroundColor(muted)
                }.padding(22).background(panel).cornerRadius(22)
            }.frame(maxWidth: 600).padding(.horizontal, 22).padding(.bottom, 30).frame(maxWidth: .infinity)
        }
    }
    private var room: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 700 {
                HStack(alignment: .top, spacing: 20) {
                    ScrollView { peoplePanel.padding(.bottom, 20) }
                    ScrollView { controls }.frame(width: 300)
                }.padding(.horizontal, 24)
            } else if geometry.size.height < 430 {
                ScrollView { VStack(spacing: 10) { peoplePanel; controls }.padding(.horizontal, 18) }
            } else {
                VStack(spacing: 10) {
                    ScrollView { peoplePanel }
                    controls
                }.padding(.horizontal, 18).padding(.bottom, 8)
            }
        }
    }
    private var peoplePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                eyebrow(model.tally == "program" ? "● PGM / ON AIR" : model.tally == "preview" ? "● PVW / NEXT" : "TALLY / STANDBY")
                Spacer(); Image(systemName: "waveform").foregroundColor(accent)
            }
            if model.adminCount > 0 { Text("ADMIN đang giám sát · \(model.adminCount)").foregroundColor(.yellow).font(.headline) }
            identity.font(.headline).fixedSize(horizontal: false, vertical: true)
            HStack { eyebrow("ĐANG NÓI"); Spacer(); Text("\(model.talkers.count)").font(.caption).foregroundColor(muted) }
            if model.talkers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.circle").font(.system(size: 46)).foregroundColor(muted)
                    Text(model.connected ? "Kênh đã sẵn sàng" : "Đang kết nối…").font(.headline)
                    Text("Tên và vai trò người đang nói sẽ hiện tại đây.").font(.caption).foregroundColor(muted).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 24)
            }
            ForEach(model.talkers) { member in
                HStack(spacing: 12) {
                    Text(String(member.name.prefix(1)).uppercased()).font(.headline).foregroundColor(ink)
                        .frame(width: 38, height: 38).background(accent).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 5) {
                        if !member.name.isEmpty { Text(member.name).font(.headline) }
                        Text(member.roleTitle).font(.caption.bold()).foregroundColor((member.role == .camera || member.role == .admin) ? .yellow : muted)
                    }
                    Spacer(); Image(systemName: "waveform").foregroundColor(accent)
                }.padding(14).background(Color(red: 0.07, green: 0.20, blue: 0.29)).cornerRadius(13)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(panel.opacity(model.tally == "off" ? 1 : 0.7)).cornerRadius(20)
    }
    private var identity: Text {
        Text(model.roomTitle(model.profile.room) + " - " + model.profile.name + " - ")
        + Text(model.profile.role == .camera ? "Camera " + String(format: "%02d", model.profile.cameraNumber) : model.profile.role.title)
            .foregroundColor(model.profile.role == .camera ? .yellow : .white)
        + Text(" - Thiết bị " + String(format: "%02d", model.profile.number))
    }
    private var gpsStatusPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("GPS · " + GPSTracker.labels[gps.choice]).font(.caption.bold())
            Text(gps.fixStatus).font(.caption2)
            Text(gps.status).font(.caption2)
            Text("Gửi thành công: " + gps.lastSent).font(.caption2)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(panel).cornerRadius(10)
    }
    private var controls: some View {
        VStack(spacing: 8) {
            if model.profile.role == .director {
                Toggle("PTT · Nhấn giữ để nói", isOn: $model.directorPTT)
                    .font(.subheadline).onChange(of: model.directorPTT) { _ in model.modeChanged() }
            }
            if model.toggleMode {
                Button { model.toggleMic() } label: { micFace }
                    .buttonStyle(.plain).disabled(!model.connected).accessibilityIdentifier("toggleMic")
            } else {
                HoldButton(title: model.micLive ? "ĐANG NÓI · THẢ ĐỂ TẮT" : model.micHeld ? "ĐANG MỞ MICRO…" : "GIỮ ĐỂ NÓI",
                           enabled: model.connected, live: model.micLive,
                           onDown: { model.startMic() }, onUp: { model.stopMic() })
                    .frame(height: 76).accessibilityIdentifier("holdMic")
            }
            HStack(spacing: 7) {
                micWaveform
                Button { model.toggleEchoCancellation() } label: {
                    Text("EC").font(.caption.bold()).frame(width: 34, height: 32)
                        .foregroundColor(model.echoActive ? accent : muted)
                        .background(model.echoCancellation ? accent.opacity(0.15) : ink).cornerRadius(8)
                }.disabled(model.micHeld)
                    .accessibilityLabel("Bật hoặc tắt khử vọng micro")
                    .accessibilityValue(model.echoStatus)
                Menu {
                    Button("Loa ngoài" + (model.speaker ? " ✓" : "")) { model.speaker = true; model.changeSpeaker() }
                    Button("Loa thoại" + (!model.speaker ? " ✓" : "")) { model.speaker = false; model.changeSpeaker() }
                    Button("Loa ON" + (!model.speakerMuted ? " ✓" : "")) { model.muteSpeaker(false) }
                    Button("Loa OFF" + (model.speakerMuted ? " ✓" : "")) { model.muteSpeaker(true) }
                } label: {
                    Image(systemName: model.speakerMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 34, height: 32).background(ink).cornerRadius(8)
                }.accessibilityLabel("Tùy chọn loa")
                AudioRoutePicker().frame(width: 30, height: 32).accessibilityLabel("Chọn tai nghe hoặc thiết bị âm thanh")
            }
            Text(model.echoStatus).font(.system(size: 10)).foregroundColor(muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.audioFailed {
                Button("Thử lại micro / loa") { model.retryAudio() }.font(.caption)
            }
            if model.audioFailed {
                Text(model.micDiagnostic).font(.caption2).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("Chi tiết âm thanh") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.micDiagnostic).fixedSize(horizontal: false, vertical: true)
                    Text(model.traffic)
                }.font(.system(size: 10, design: .monospaced)).foregroundColor(muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.font(.caption2).foregroundColor(muted)
            Button("Rời kênh / Đổi thiết bị") { model.leave() }.font(.subheadline).padding(.vertical, 5)
            Text("Ưu tiên tai nghe khi các máy ở gần nhau để tránh vọng âm.").font(.system(size: 10)).foregroundColor(muted).multilineTextAlignment(.center)
        }.padding(12).background(panel.opacity(0.95)).cornerRadius(18)
    }
    private var micWaveform: some View {
        HStack(spacing: 8) {
            VStack(spacing: 2) {
                Image(systemName: model.micLive ? "mic.fill" : "mic.slash.fill")
                Text(model.micLive ? "MIC" : "TẮT").font(.system(size: 8))
            }.font(.caption)
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(0..<18, id: \.self) { index in
                        let value = model.micLive ? model.micLevels[index * 2] : 0
                        Capsule().fill(value > 0.9 ? Color.orange : accent)
                            .frame(width: max(1, (geometry.size.width - 34) / 18), height: max(2, CGFloat(value) * 20))
                    }
                }.frame(height: 22)
            }.frame(height: 22)
        }.foregroundColor(muted).accessibilityElement(children: .ignore)
            .accessibilityLabel(model.micLive ? "Mức âm thanh micro đang phát" : "Micro đang tắt")
    }
    private var micFace: some View {
        VStack(spacing: 6) {
            Text(model.micHeld ? (model.micLive ? "TẮT MICRO" : "ĐANG MỞ MICRO…") : "BẬT MICRO").font(.headline)
            Text(model.micHeld ? "VẪN NGHE CÁC THÀNH VIÊN" : "CHẠM ĐỂ BẬT / TẮT").font(.system(size: 10))
        }.frame(maxWidth: .infinity).frame(height: 76)
            .foregroundColor(model.micLive ? .orange : accent)
            .background(model.micLive ? Color.orange.opacity(0.13) : accent.opacity(0.12)).cornerRadius(15)
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(model.micLive ? Color.orange : accent.opacity(0.5)))
            .opacity(model.connected ? 1 : 0.45)
    }
    private var devicesSheet: some View {
        NavigationView {
            List(model.sortedMembers) { member in
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        if !member.name.isEmpty { Text((model.talkers.contains(where: { $0.id == member.id }) ? "● " : "○ ") + member.name).font(.headline) }
                        Text(member.roleTitle).foregroundColor((member.role == .camera || member.role == .admin) ? .yellow : muted).font(.subheadline)
                    }
                    Spacer(); Text("Thiết bị " + String(format: "%02d", member.number)).font(.caption)
                }.padding(.vertical, 5)
            }.navigationTitle("Devices · \(model.members.count)/\(model.roomLimit)")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Đóng") { showDevices = false; showGPS = false } } }
        }.navigationViewStyle(.stack)
    }
    private func eyebrow(_ text: String) -> some View { Text(text).font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundColor(muted) }
    private func selection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack { Text(title).font(.caption.bold()).foregroundColor(muted); Spacer(); content().pickerStyle(.menu) }
            .padding(.horizontal, 12).padding(.vertical, 5).background(ink).cornerRadius(10)
    }
}

// UIControl delivers touch-up-outside and cancellation, preventing a latched hold-to-talk.
struct HoldButton: UIViewRepresentable {
    var title: String
    var enabled: Bool
    var live: Bool
    var onDown: () -> Void
    var onUp: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .custom)
        button.layer.cornerRadius = 15; button.layer.borderWidth = 1
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        button.titleLabel?.adjustsFontSizeToFitWidth = true; button.titleLabel?.minimumScaleFactor = 0.6
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        button.addTarget(context.coordinator, action: #selector(Coordinator.down), for: .touchDown)
        button.addTarget(context.coordinator, action: #selector(Coordinator.up), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.owner = self
        let color = live ? UIColor.systemOrange : UIColor(red: 0.47, green: 0.75, blue: 1, alpha: 1)
        button.setTitle(title, for: .normal); button.setTitleColor(color, for: .normal)
        button.backgroundColor = color.withAlphaComponent(0.12); button.layer.borderColor = color.withAlphaComponent(0.5).cgColor
        button.isEnabled = enabled; button.alpha = enabled ? 1 : 0.45
    }
    final class Coordinator: NSObject {
        var owner: HoldButton
        init(_ owner: HoldButton) { self.owner = owner }
        @objc func down() { owner.onDown() }
        @objc func up() { owner.onUp() }
    }
}
struct AudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { let view = AVRoutePickerView(); view.tintColor = .systemBlue; return view }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
