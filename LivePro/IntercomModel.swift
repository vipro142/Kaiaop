import Foundation
import Combine
import AVFoundation
import UIKit
import MediaPlayer

final class IntercomModel: ObservableObject {
    @Published var selectedServer: IntercomServer = .hanoi
    private var rejoinAfterServerSwitch = false
    @Published var profile: JoinProfile
    @Published var roomIDs = JoinProfile.rooms
    @Published var roomNames: [String: String] = [:]
    func roomTitle(_ room: String) -> String { roomNames[room] ?? ("Sự kiện " + String(room.suffix(1))) }
    @Published var roomPassword = ""
    @Published var passwordRequired = false
    private var passwordRoom = ""
    @Published var roomLimit = 30
    @Published var adminCount = 0
    @Published var freeNumbers: [Int] = []
    @Published var availabilityText = "Đang kiểm tra số trống…"
    @Published var roomClosed = false
    private var closedWarningKey = ""
    @Published var canJoin = false
    @Published var joining = false
    @Published var inRoom = false { didSet { syncBluetoothTally() } }
    @Published var connected = false { didSet { syncBluetoothTally() } }
    @Published var connectionText = "Chưa tham gia"
    @Published var members: [Member] = []
    @Published var talkers: [Member] = []
    @Published var tally = "off" { didSet { syncBluetoothTally() } }
    let bluetoothTally = BluetoothTally()
    @Published var directorPTT = false
    @Published var micHeld = false
    @Published var echoCancellation = true
    @Published var echoActive = false
    @Published var voiceIsolationActive = false
    @Published var voiceIsolationStatus = "Tách giọng chưa bật"
    @Published var echoStatus = "EC đang kiểm tra"
    @Published var audioFailed = false
    @Published var micDiagnostic = "Micro đang tắt"
    @Published var micLive = false
    @Published var micLevels: [Double] = Array(repeating: 0, count: 36)
    @Published var speaker = true
    @Published var speakerMuted = false
    @Published var volume: Double = 0.75
    @Published var traffic = "↑ Gửi 0 KB   ·   ↓ Nhận 0 KB"
    @Published var notice: String?
    private let clientID: String
    private let transport: IntercomTransport
    private let audio = VoiceAudio()
    private var availabilityTimer: Timer?
    private var queryBusy = false
    private var queryVersion = 0
    private var noticeVersion = 0
    private var conflictKey = ""
    private var micVersion = 0
    private var latched = false
    private var joiningVersion = 0
    private var listeners: [NSObjectProtocol] = []
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var appActive = true
    var toggleMode: Bool { profile.role == .director && !directorPTT }
    var sortedMembers: [Member] { members.sorted { $0.number < $1.number } }

    init() {
        let defaults = UserDefaults.standard
        echoCancellation = (defaults.object(forKey: "echoCancellation") as? Bool) ?? true
        if let data = defaults.data(forKey: "profile"), let p = try? JSONDecoder().decode(JoinProfile.self, from: data) { profile = p }
        else { profile = JoinProfile() }
        let storedID = defaults.string(forKey: "clientID") ?? UUID().uuidString
        clientID = storedID; defaults.set(storedID, forKey: "clientID")
        transport = IntercomTransport(clientID: storedID)
        selectedServer = IntercomServer(rawValue: defaults.string(forKey: "intercomServer") ?? "hanoi") ?? .hanoi
        transport.selectServer(selectedServer)
        audio.echoCancellation = echoCancellation
        transport.onConnection = { [weak self] state in self?.connection(state) }
        transport.onServerActivity = { [weak self] in self?.bluetoothTally.serverMessageReceived() }
        transport.onMessage = { [weak self] message in self?.message(message) }
        transport.onAudio = { [weak self] data in self?.audio.play(data) }
        transport.onTraffic = { [weak self] tx, rx in self?.traffic = String(format: "↑ Gửi %.1f KB   ·   ↓ Nhận %.1f KB", Double(tx)/1024, Double(rx)/1024) }
        audio.onNeedsRecovery = { [weak self] reason in
            guard let self = self, self.inRoom else { return }
            self.stopMic(); self.audio.stop(deactivate: false)
            self.audioFailed = true
            self.micDiagnostic = "Audio STOP · " + reason
            self.showNotice(reason, seconds: 20)
        }
        audio.onEchoStatus = { [weak self] status, enabled in
            self?.echoStatus = status; self?.echoActive = enabled; self?.refreshMicrophoneMode()
        }
        audio.onDiagnostic = { [weak self] text in self?.micDiagnostic = text }
        transport.onSendError = { [weak self] text in self?.showNotice(text) }
        audio.onLevel = { [weak self] level in
            guard let self = self else { return }
            if !self.micLive { self.micLevels = Array(repeating: 0, count: 36); return }
            self.micLevels = Array(self.micLevels.dropFirst()) + [level]
        }
        audio.onPCM = { [weak self] data in self?.transport.audio(data) }
        let center = NotificationCenter.default
        listeners.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self = self, self.inRoom,
                  let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            self.stopMic()
            if type == .began { self.audio.stop(deactivate: false); self.showNotice("Âm thanh bị gián đoạn bởi cuộc gọi hoặc ứng dụng khác.") }
            else { self.restartAudio() }
        })
        listeners.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self = self, self.inRoom,
                  let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                  reason == .oldDeviceUnavailable || reason == .newDeviceAvailable else { return }
            self.stopMic(); self.audio.stop(deactivate: false); self.restartAudio()
        })
        listeners.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.inRoom else { return }; self.stopMic(); self.audio.stop(deactivate: false); self.restartAudio()
        })
        availabilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshAvailability() }
        installHeadsetCommands()
        refreshAvailability()
    }
    deinit { remoteTargets.forEach { $0.0.removeTarget($0.1) }; availabilityTimer?.invalidate(); listeners.forEach { NotificationCenter.default.removeObserver($0) } }
    func selectServer(_ server: IntercomServer) {
        guard server != selectedServer else { return }
        leave()
        selectedServer = server
        UserDefaults.standard.set(server.rawValue, forKey: "intercomServer")
        transport.selectServer(server)
        queryVersion += 1; queryBusy = false; canJoin = false
        roomNames = [:]; roomIDs = JoinProfile.rooms; freeNumbers = []
        passwordRequired = false; roomPassword = ""; roomClosed = false
        closedWarningKey = ""; conflictKey = ""
        rejoinAfterServerSwitch = false
        connectionText = server.title
        refreshAvailability()
    }
    func selectionChanged() {
        roomClosed = false
        if passwordRoom != profile.room { roomPassword = ""; passwordRoom = profile.room }
        queryVersion += 1; conflictKey = ""; canJoin = false
        refreshAvailability()
    }
    func refreshAvailability() {
        guard !inRoom, !joining, !queryBusy, appActive else { return }
        queryBusy = true; let version = queryVersion
        transport.availability(profile) { [weak self] result in
            guard let self = self, version == self.queryVersion else { return }; self.queryBusy = false
            guard !self.inRoom, !self.joining else { return }
            switch result {
            case .failure:
                self.canJoin = false; self.availabilityText = "Chưa kết nối máy chủ. Đang thử lại…"
            case .success(let json):
                guard json["type"] as? String == "availability" else { self.canJoin = false; return }
                self.passwordRequired = json["passwordRequired"] as? Bool == true
                self.roomNames = (json["roomNames"] as? [String: String]) ?? self.roomNames
                self.roomIDs = self.roomNames.keys.sorted()
                if !self.roomIDs.contains(self.profile.room), let first = self.roomIDs.first { self.profile.room = first; self.roomPassword = ""; self.canJoin = false; self.queryVersion += 1; return }
                self.roomLimit = (json["limit"] as? Int) ?? 30
                self.freeNumbers = (json["available"] as? [Int] ?? []).filter { (1...300).contains($0) }
                let selected = (json["selectedNumber"] as? Int) ?? 0
                if self.freeNumbers.contains(selected) { self.profile.number = selected }
                let conflict = self.profile.role == .camera && json["cameraConflict"] as? Bool == true
                self.roomClosed = json["enabled"] as? Bool == false && self.roomIDs.contains(self.profile.room)
                if self.roomClosed && self.closedWarningKey != self.profile.room { self.showRoomClosed() }
                else if !self.roomClosed { self.closedWarningKey = "" }
                self.canJoin = selected > 0 && !conflict
                self.availabilityText = conflict ? "Trùng số camera. Hãy chọn camera khác." : selected > 0
                    ? "Còn \(self.freeNumbers.count)/\(self.roomLimit) số trống · Đã giữ số \(String(format: "%02d", selected))" : "Phòng đã đủ chỗ hoặc đang tắt."
                let key = "\(self.profile.room):\(self.profile.cameraNumber)"
                if conflict && self.conflictKey != key { self.conflictKey = key; self.showNotice("Trùng số camera. Vui lòng chọn lại.", seconds: 1.5) }
                if self.rejoinAfterServerSwitch {
                    self.rejoinAfterServerSwitch = false
                    if self.canJoin && !self.roomClosed && !self.passwordRequired { self.join() }
                    else { self.showNotice("Đã đổi sang " + self.selectedServer.title + ". Kiểm tra phòng và mật khẩu để tham gia.") }
                }
            }
        }
    }
    func showRoomClosed() { closedWarningKey = profile.room; showNotice("Phòng đã khóa. Liên hệ ADMIN để mở phòng.", seconds: 2) }
    func dismissNotice() { noticeVersion += 1; notice = nil }
    func join() {
        if roomClosed { showRoomClosed(); return }
        guard canJoin, !joining else { return }
        if passwordRequired && roomPassword.isEmpty { showNotice("Nhập mật khẩu sự kiện."); return }
        profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard profile.valid else { showNotice("Nhập tên hợp lệ (tối đa 40 ký tự) và chọn đủ cấu hình."); return }
        joining = true; joiningVersion += 1; let token = joiningVersion
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self = self, token == self.joiningVersion else { return }
                self.joining = false
                guard self.appActive else { self.showNotice("Mở ứng dụng để bắt đầu phiên liên lạc."); return }
                guard allowed else { self.showNotice("Cần quyền Microphone. Mở Cài đặt → LIVEPRO Intercom → Microphone."); return }
                do {
                    self.audio.speaker = self.speaker; try self.audio.start(); self.audioFailed = false
                    self.inRoom = true; self.remoteControls(true); self.directorPTT = false; self.tally = "off"; self.traffic = "↑ Gửi 0 KB   ·   ↓ Nhận 0 KB"
                    self.save(); self.transport.join(self.profile, password: self.passwordRequired ? self.roomPassword : ""); UIApplication.shared.isIdleTimerDisabled = true
                } catch {
                    self.audio.stop()
                    self.audioFailed = true
                    self.micDiagnostic = error.localizedDescription
                    self.showNotice("Không mở được âm thanh: \(error.localizedDescription)", seconds: 20)
                }
            }
        }
    }
    private func save() { if let data = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(data, forKey: "profile") } }
    func leave() {
        rejoinAfterServerSwitch = false
        roomPassword = ""; joiningVersion += 1; joining = false; stopMic(); transport.leave(); audio.stop()
        connected = false; inRoom = false; remoteControls(false); members = []; talkers = []; tally = "off"; connectionText = "Chưa tham gia"
        UIApplication.shared.isIdleTimerDisabled = false; queryVersion += 1; refreshAvailability()
    }
    private func connection(_ state: String) {
        connected = state == "ready"
        connectionText = connected ? "Đã kết nối" : state == "offline" ? "Đang nối lại…" : "Đang kết nối…"
        if !connected { stopMic(); audio.flushPlayback(); members = []; talkers = []; tally = "off" }
    }
    private func message(_ json: [String: Any]) {
        switch json["type"] as? String {
        case "room_config": roomNames[profile.room] = (json["name"] as? String) ?? roomTitle(profile.room); roomLimit = (json["limit"] as? Int) ?? roomLimit
        case "admin_presence": adminCount = (json["admins"] as? [[String: Any]] ?? []).count
        case "kicked": leave(); if json["reason"] as? String == "room_closed" { showRoomClosed() } else { showNotice("Bạn đã rời phòng theo yêu cầu quản trị.") }
        case "registered":
            roomNames[profile.room] = (json["roomName"] as? String) ?? roomTitle(profile.room)
            roomLimit = (json["limit"] as? Int) ?? 30
            adminCount = (json["admins"] as? [[String: Any]] ?? []).count
            if let n = json["number"] as? Int { profile.number = n; save() }
            members = (json["members"] as? [[String: Any]] ?? []).compactMap(Member.init)
            talkers = (json["talkers"] as? [[String: Any]] ?? []).compactMap(Member.init)
            if json["reassigned"] as? Bool == true { showNotice("Đã chuyển sang số thiết bị \(profile.number).") }
        case "device_online":
            if let person = Member(json) { members.removeAll { $0.id == person.id }; members.append(person) }
        case "device_offline":
            let id = (json["deviceId"] as? String) ?? ""; members.removeAll { $0.id == id }; talkers.removeAll { $0.id == id }
        case "talkers": talkers = (json["talkers"] as? [[String: Any]] ?? []).compactMap(Member.init)
        case "ptt_start": if let person = Member(json) { talkers.removeAll { $0.id == person.id }; talkers.append(person) }
        case "ptt_stop": talkers.removeAll { $0.id == json["deviceId"] as? String }
        case "ptt_granted":
            if micHeld && connected { micLive = true; micDiagnostic = "Đang kiểm tra đầu vào micro…"; audio.setTransmitting(true) } else { transport.microphone(false) }
        case "ptt_busy", "ptt_revoked": stopMic(); showNotice("Máy chủ chưa mở micro. Hãy thử lại.")
        case "tally": tally = (json["state"] as? String) ?? "off"
        case "error":
            let code = (json["message"] as? String) ?? "unknown"
            stopMic()
            if code == "room_closed" { leave(); showRoomClosed(); return }
            if ["room_password_invalid", "room_closed", "upgrade_required", "camera_in_use", "event_full", "device_in_use", "invalid_device_identity", "name_required_or_invalid"].contains(code) { leave() }
            showNotice(["room_password_invalid":"Mật khẩu sự kiện không đúng. Hãy nhập lại.","camera_in_use":"Trùng số camera. Hãy chọn lại.","event_full":"Phòng đã đủ chỗ hoặc đang tắt.","device_in_use":"Số thiết bị đã được dùng."][code] ?? "Máy chủ: \(code)")
        default: break
        }
    }
    private func installHeadsetCommands() {
        let center = MPRemoteCommandCenter.shared()
        for command in [center.playCommand, center.pauseCommand, center.stopCommand, center.togglePlayPauseCommand] {
            command.isEnabled = false
            let token = command.addTarget { [weak self] _ in
                guard let self = self else { return .commandFailed }
                DispatchQueue.main.async {
                    guard self.inRoom, self.connected else { return }
                    if command === center.pauseCommand || command === center.stopCommand { self.stopMic() }
                    else if command === center.playCommand { self.startMic(latch: true) }
                    else { self.toggleMic() }
                    self.showNotice(self.micHeld ? "Tai nghe: micro đang bật. Bấm lại để tắt." : "Tai nghe: đã tắt micro.")
                }
                return .success
            }
            remoteTargets.append((command, token))
        }
    }
    private func remoteControls(_ active: Bool) {
        remoteTargets.forEach { $0.0.isEnabled = active }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = active ? [
            MPMediaItemPropertyTitle: "LIVEPRO · " + roomTitle(profile.room),
            MPMediaItemPropertyArtist: "Bấm nút tai nghe để bật / tắt micro",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: micHeld ? 1.0 : 0.0
        ] : nil
    }
    func startMic(latch: Bool = false) {
        guard connected, !micHeld else { return }
        do { try audio.start(); audioFailed = false }
        catch { audioFailed = true; micDiagnostic = error.localizedDescription; showNotice("Không mở được micro: \(error.localizedDescription)", seconds: 20); return }
        micVersion += 1; latched = latch; micHeld = true; remoteControls(inRoom); transport.microphone(true)
    }
    func stopMic() { micVersion += 1; latched = false; micHeld = false; micLive = false; remoteControls(inRoom); audio.setTransmitting(false); transport.microphone(false) }
    func toggleMic() { if micHeld { stopMic() } else { startMic(latch: true) } }
    func modeChanged() { stopMic() }
    func setVolume() { audio.volume = speakerMuted ? 0 : Float(volume) }
    func muteSpeaker(_ muted: Bool) { speakerMuted = muted; setVolume() }
    func changeSpeaker() { stopMic(); audio.speaker = speaker; if inRoom { audio.stop(deactivate: false); restartAudio() } }
    private func refreshMicrophoneMode() {
        voiceIsolationActive = AVCaptureDevice.activeMicrophoneMode == .voiceIsolation
        if voiceIsolationActive { voiceIsolationStatus = "Tách giọng bật" }
        else if AVCaptureDevice.preferredMicrophoneMode == .voiceIsolation {
            voiceIsolationStatus = "Tách giọng đã chọn, chưa áp dụng"
        } else { voiceIsolationStatus = "Tách giọng chưa bật" }
    }
    func openMicrophoneModes() {
        guard inRoom, audio.running, !micHeld else { return }
        refreshMicrophoneMode()
        AVCaptureDevice.showSystemUserInterface(.microphoneModes)
    }
    func toggleEchoCancellation() {
        echoCancellation.toggle()
        UserDefaults.standard.set(echoCancellation, forKey: "echoCancellation")
        audio.echoCancellation = echoCancellation
        if inRoom { retryAudio() }
    }
    func retryAudio() {
        guard inRoom else { return }
        stopMic(); audio.stop(deactivate: false); restartAudio()
    }
    private func restartAudio() {
        guard inRoom else { return }
        do { try audio.start(); audioFailed = false }
        catch {
            audioFailed = true; micDiagnostic = "Audio STOP · " + error.localizedDescription
            showNotice(error.localizedDescription, seconds: 20)
        }
    }
    func activeChanged(_ active: Bool) {
        appActive = active
        syncBluetoothTally(); bluetoothTally.sceneChanged(active: active)
        if BackgroundMicPolicy.shouldRelease(active: active, latched: latched) { stopMic() }
        if active { if inRoom && !audio.running && !audioFailed { restartAudio() } else { refreshAvailability() } }
    }
    private func syncBluetoothTally() { bluetoothTally.update(tally: tally, sessionHealthy: connected && inRoom) }
    func showNotice(_ text: String, seconds: Double = 4) {
        noticeVersion += 1; let token = noticeVersion; notice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            if self?.noticeVersion == token { self?.notice = nil }
        }
    }
}
