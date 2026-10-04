import Foundation
import Combine
import CoreBluetooth
import CryptoKit

struct TallyDevice: Identifiable { let id: UUID; var name: String; var rssi: Int; var claimed: Bool = false }
final class BluetoothTally: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let serviceUUID = CBUUID(string: TallyBLEProtocol.serviceUUID)
    static let stateUUID = CBUUID(string: TallyBLEProtocol.stateUUID)
    static let authUUID = CBUUID(string: "8f7a0004-7c3b-4a84-9c10-4e4154590001")
    static let ownerUUID = CBUUID(string: "8f7a0005-7c3b-4a84-9c10-4e4154590001")
    static let releaseUUID = CBUUID(string: "8f7a0006-7c3b-4a84-9c10-4e4154590001")
    static let infoUUID = CBUUID(string: "8f7a0007-7c3b-4a84-9c10-4e4154590001")
    static let brightnessUUID = CBUUID(string: "8f7a0008-7c3b-4a84-9c10-4e4154590001")
    private static let key: [UInt8] = [0xf9,0x7d,0x62,0xb1,0x6e,0x41,0x25,0x8b,0x41,0xfd,0x1f,0xca,0x82,0xe7,0x54,0x23,0x8b,0xbe,0x74,0x88,0x19,0x94,0xc3,0x20,0x7e,0x5c,0x20,0x86,0x77,0x49,0xed,0xb5]
    @Published var selectionNotice: String?
    @Published private(set) var devices: [TallyDevice] = []
    @Published private(set) var status = "Chưa kết nối"
    @Published private(set) var ready = false
    @Published private(set) var busy = false
    @Published private(set) var scanning = false
    @Published private(set) var connectedName = ""
    @Published private(set) var rememberedName: String
    @Published private(set) var accessoryState: UInt8 = 0
    @Published private(set) var brightnessAvailable = false
    @Published private(set) var brightnessSelection = 5
    @Published private(set) var brightnessStatus = "Đang đọc độ sáng…"
    private var brightnessKnown = false
    private var brightnessLevel = 5
    private var pendingBrightness: UInt8?
    private var writtenBrightness: UInt8 = 5
    private var brightnessWaiting = false
    private var brightnessReadNeeded = false
    private var brightnessSaveAt: TimeInterval = 0
    private let defaults: UserDefaults
    private let ownerToken: [UInt8]
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var ownershipFrames: [UUID: Data] = [:]
    private var rememberedID: UUID?
    private var wanted: Bool
    private var stopWanted: Bool
    private var nextDevice: TallyDevice?
    private var nextMode: UInt8 = 1
    private var selectionCandidate: TallyDevice?
    private var awaitingLegacyRelease = false
    private var searchWanted = false
    private var stateCharacteristic: CBCharacteristic?
    private var authCharacteristic: CBCharacteristic?
    private var ownerCharacteristic: CBCharacteristic?
    private var releaseCharacteristic: CBCharacteristic?
    private var infoCharacteristic: CBCharacteristic?
    private var brightnessCharacteristic: CBCharacteristic?
    private var claimMode: UInt8 = 0
    private var releaseRequested = false
    private var releaseReading = false
    private var requestedState: UInt8 = 0
    private var desiredState: UInt8 = 0
    private var lastServerMessage = -TimeInterval.infinity
    private var pendingState: UInt8?
    private enum Write { case claim, authentication, release, readInfo, state(UInt8), brightness(UInt8), readBrightness }
    private var inFlight: Write?
    private var authenticationStage = 0
    private var operationAt: TimeInterval = 0
    private var connectionAt: TimeInterval = 0
    private var heartbeat: DispatchSourceTimer?
    private var retry: DispatchWorkItem?
    private var scanStop: DispatchWorkItem?

    override convenience init() { self.init(defaults: .standard) }
    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let saved = defaults.data(forKey: "bleTallyOwnerToken"), saved.count == 16 { ownerToken = Array(saved) }
        else { var uuid = UUID().uuid; ownerToken = withUnsafeBytes(of: &uuid) { Array($0) }; defaults.set(Data(ownerToken), forKey: "bleTallyOwnerToken") }
        rememberedName = defaults.string(forKey: "bleTallyName") ?? ""
        rememberedID = defaults.string(forKey: "bleTallyID").flatMap(UUID.init(uuidString:))
        stopWanted = defaults.bool(forKey: "bleTallyPendingStop")
        wanted = rememberedID != nil && (defaults.bool(forKey: "bleTallyAutoReconnect") || stopWanted)
        super.init()
        let timer = DispatchSource.makeTimerSource(queue: .main); timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.tick() }; heartbeat = timer; timer.resume()
        if wanted { startCentral() }
    }
    deinit { heartbeat?.cancel(); retry?.cancel(); scanStop?.cancel() }
    static func validAdvertisement(_ data: Data?) -> Bool {
        guard let data = data, data.count == 6 else { return false }; let b = Array(data)
        return b[0] == 0xff && b[1] == 0xff && b[2] == 0x4c && b[3] == 0x50 && (b[4] == 1 || b[4] == 2)
    }
    static func claimedAdvertisement(_ data: Data?) -> Bool { validAdvertisement(data) && Array(data!)[5] & 3 != 0 }
    static func inUseAdvertisement(_ data: Data?) -> Bool { claimedAdvertisement(data) && Array(data!)[5] & 2 != 0 }
    static func isTallyName(_ value: String) -> Bool { value.lowercased().hasPrefix("tally") }
    static func stateByte(_ tally: String, sessionHealthy: Bool) -> UInt8 { TallyBLEProtocol.stateByte(tally, sessionHealthy: sessionHealthy) }
    static func proof(_ nonce: Data, token: [UInt8], manual: Bool) -> Data? { proof(nonce, token: token, mode: manual ? 1 : 0) }
    static func proof(_ nonce: Data, token: [UInt8], mode: UInt8) -> Data? {
        guard nonce.count == 16 && token.count == 16 && mode <= 3 else { return nil }
        var message = nonce; message.append(mode); message.append(contentsOf: token)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)).prefix(16))
    }
    var canAdjustBrightness: Bool { ready && !stopWanted && brightnessAvailable && brightnessKnown }
    func openSettings() { guard ready && !stopWanted else { return }; if brightnessAvailable { brightnessReadNeeded = true; brightnessStatus = "Đang đọc độ sáng…"; pump() } else { brightnessStatus = "Cần firmware Tally 2.4 để chỉnh độ sáng" } }
    func setBrightness(_ value: Int) { guard canAdjustBrightness else { return }; let level = min(5,max(1,value)); brightnessSelection = level; pendingBrightness = UInt8(level); brightnessSaveAt = ProcessInfo.processInfo.systemUptime + 0.3; brightnessStatus = "Đang lưu độ sáng…"; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.pump() } }
    var connectedID: UUID? { ready && !stopWanted ? peripheral?.identifier : nil }
    var canTransferSelection: Bool { selectionCandidate != nil }
    func dismissSelection() { selectionNotice = nil; selectionCandidate = nil }
    func confirmTakeover() { guard let device = selectionCandidate else { return }; dismissSelection(); select(device, mode: 2) }
    private func showOccupied(_ device: TallyDevice, uncertain: Bool = false) {
        selectionCandidate = device
        selectionNotice = (uncertain ? "Tally chưa phản hồi; có thể đang được thiết bị khác giữ. " : "Tally này đã được chọn. ") + "Hãy chọn tally khác, chuyển sang thiết bị này hoặc giữ nút BOOT trên tally 3 giây để reset liên kết và pair lại."
    }
    func update(tally: String, sessionHealthy: Bool) { requestedState = Self.stateByte(tally, sessionHealthy: sessionHealthy); refreshState() }
    func serverMessageReceived() { lastServerMessage = ProcessInfo.processInfo.systemUptime; refreshState() }
    private func refreshState() {
        let value = stopWanted ? UInt8(0) : TallyBLEProtocol.liveState(requestedState, serverAge: ProcessInfo.processInfo.systemUptime - lastServerMessage)
        if desiredState != value { desiredState = value; pendingState = value; pump() }
    }
    func sceneChanged(active: Bool) { if active && wanted { refreshState(); startCentral(); reconnect() } }
    func scan() { devices.removeAll(); ownershipFrames.removeAll(); retainConnectedDevice(); searchWanted = true; startCentral(); if central?.state == .poweredOn { beginScan() } }
    private func retainConnectedDevice() { guard ready, let p = peripheral else { return }; if !devices.contains(where: { $0.id == p.identifier }) { devices.insert(TallyDevice(id: p.identifier, name: connectedName, rssi: 0, claimed: true), at: 0) } }
    func stopScan() { scanStop?.cancel(); scanStop = nil; searchWanted = false; scanning = false; central?.stopScan() }
    private func startCentral() { if central == nil { central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionRestoreIdentifierKey: "com.livepro.intercom.tally-central", CBCentralManagerOptionShowPowerAlertKey: true]) } }
    private func remember(_ device: TallyDevice) {
        rememberedID = device.id; rememberedName = device.name; wanted = true
        defaults.set(device.id.uuidString, forKey: "bleTallyID"); defaults.set(device.name, forKey: "bleTallyName"); defaults.set(true, forKey: "bleTallyAutoReconnect")
    }
    func connect(_ device: TallyDevice) { if device.claimed || (wanted && rememberedID == device.id) { showOccupied(device); return }; select(device, mode: 1) }
    private func select(_ device: TallyDevice, mode: UInt8) {
        guard peripherals[device.id] != nil else { return }
        if ready && peripheral?.identifier == device.id { status = "Thành công · Đã kết nối \(device.name)"; return }
        if stopWanted || (wanted && rememberedID != nil && rememberedID != device.id) { nextDevice = device; nextMode = mode; beginStop(); return }
        stopScan(); retry?.cancel()
        if let old = peripheral { nextDevice = device; nextMode = mode; central?.cancelPeripheralConnection(old); return }
        remember(device); if let p = peripherals[device.id] { attach(p, mode: mode) }
    }
    func reconnectRemembered() { guard rememberedID != nil else { return }; wanted = true; defaults.set(true, forKey: "bleTallyAutoReconnect"); startCentral(); reconnect() }
    // Retain the owner/address until the device confirms durable release.
    func disconnect() { nextDevice = nil; beginStop() }
    private func beginStop() {
        if stopWanted { return }; pendingBrightness = nil; stopWanted = true; defaults.set(true, forKey: "bleTallyPendingStop"); stopScan(); retry?.cancel()
        guard rememberedID != nil else { completeStop(); return }
        wanted = true; defaults.set(true, forKey: "bleTallyAutoReconnect"); status = "Đang Stop · Chờ ESP32 xóa liên kết…"
        if let p = peripheral { if ready { releaseRequested = true; pump() } else { central?.cancelPeripheralConnection(p) } }
        else { startCentral(); reconnect() }
    }
    private func forget() {
        wanted = false; stopWanted = false; awaitingLegacyRelease = false; rememberedID = nil; rememberedName = ""; retry?.cancel(); stopScan()
        defaults.removeObject(forKey: "bleTallyID"); defaults.removeObject(forKey: "bleTallyName"); defaults.removeObject(forKey: "bleTallyPendingStop"); defaults.set(false, forKey: "bleTallyAutoReconnect")
        let old = peripheral; clearConnection(); if let p = old { central?.cancelPeripheralConnection(p) }
    }
    private func completeStop(_ message: String = "Đã Stop · Tally ở Standby, chờ kết nối mới") {
        let device = nextDevice; let mode = nextMode; nextDevice = nil; forget(); status = message
        if let device = device { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.select(device, mode: mode) } }
    }
    private func beginScan() {
        guard central?.state == .poweredOn else { return }
        central?.scanForPeripherals(withServices: searchWanted ? nil : [Self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]); scanning = true
        status = stopWanted ? "Stop đang chờ · Tìm \(rememberedName)" : ready ? "Thành công · \(connectedName) · Đang Search" : "Đang Search…"
        if searchWanted {
            scanStop?.cancel(); let work = DispatchWorkItem { [weak self] in guard let self = self else { return }; self.stopScan(); if !self.stopWanted { self.status = self.ready ? "Thành công · Đã kết nối \(self.connectedName)" : self.devices.isEmpty ? "Không tìm thấy Tally" : "Chọn Tally để kết nối" } }; scanStop = work; DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
        }
    }
    private func reconnect() { guard wanted, peripheral == nil, let id = rememberedID, let central = central, central.state == .poweredOn else { return }; if stopWanted && awaitingLegacyRelease { beginScan(); return }; if let p = central.retrievePeripherals(withIdentifiers: [id]).first { attach(p) } else { beginScan() } }
    private func attach(_ p: CBPeripheral, mode: UInt8 = 0) {
        guard peripheral == nil, central?.state == .poweredOn else { return }; central?.stopScan(); scanning = false; retry?.cancel(); peripheral = p; peripherals[p.identifier] = p; p.delegate = self
        busy = true; ready = false; connectedName = rememberedName; claimMode = mode; connectionAt = ProcessInfo.processInfo.systemUptime
        status = stopWanted ? "Stop đang chờ · Kết nối \(connectedName)" : "Đang kết nối · \(connectedName)"
        if p.state == .connected { p.discoverServices([Self.serviceUUID]) } else { central?.connect(p, options: nil) }
    }
    private func clearConnection() { brightnessCharacteristic = nil; brightnessAvailable = false; brightnessKnown = false; brightnessReadNeeded = false; brightnessWaiting = false; pendingBrightness = nil; brightnessStatus = "Mất kết nối · Chờ kết nối lại Tally"; ready = false; busy = false; peripheral = nil; stateCharacteristic = nil; authCharacteristic = nil; ownerCharacteristic = nil; releaseCharacteristic = nil; infoCharacteristic = nil; releaseRequested = false; releaseReading = false; inFlight = nil; pendingState = nil; accessoryState = 0; connectedName = ""; authenticationStage = 0 }
    private func afterDisconnect() {
        if !stopWanted, let device = nextDevice { let mode = nextMode; nextDevice = nil; select(device, mode: mode); return }
        if stopWanted && awaitingLegacyRelease { beginScan(); return }
        if wanted { let work = DispatchWorkItem { [weak self] in self?.reconnect() }; retry = work; DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work) }
    }
    private func fail(_ message: String) { status = stopWanted ? "Stop đang chờ · \(message)" : "Thất bại · \(message)"; if let p = peripheral { central?.cancelPeripheralConnection(p) } }
    private func tick() {
        refreshState(); let now = ProcessInfo.processInfo.systemUptime
        if peripheral != nil && !ready && now - connectionAt > 15 {
            if !stopWanted && claimMode != 0, let p = peripheral { let device = TallyDevice(id: p.identifier, name: rememberedName, rssi: 0); forget(); status = "Thất bại · Tally chưa phản hồi"; showOccupied(device, uncertain: true) }
            else { fail("Không kết nối được \(rememberedName)") }; return
        }
        if inFlight != nil && now - operationAt > 3.5 { fail("Tally chưa phản hồi"); return }
        if ready && wanted { pendingState = desiredState; pump() }
    }
    private func pump() {
        guard inFlight == nil, ready, let p = peripheral else { return }
        if stopWanted { if releaseRequested, let release = releaseCharacteristic { releaseRequested = false; inFlight = .release; operationAt = ProcessInfo.processInfo.systemUptime; p.writeValue(Data([1]), for: release, type: .withResponse) }; return }
        if let characteristic = brightnessCharacteristic {
            if brightnessReadNeeded { brightnessReadNeeded = false; inFlight = .readBrightness; operationAt = ProcessInfo.processInfo.systemUptime; p.readValue(for: characteristic); return }
            if !brightnessWaiting, let level = pendingBrightness, ProcessInfo.processInfo.systemUptime >= brightnessSaveAt { pendingBrightness = nil; writtenBrightness = level; brightnessWaiting = true; inFlight = .brightness(level); operationAt = ProcessInfo.processInfo.systemUptime; p.writeValue(Data([level]), for: characteristic, type: .withResponse); return }
        }
        guard wanted, let value = pendingState, let state = stateCharacteristic else { return }; pendingState = nil; inFlight = .state(value); operationAt = ProcessInfo.processInfo.systemUptime; p.writeValue(Data([value]), for: state, type: .withResponse)
    }
    private func readInfo() { guard stopWanted, let p = peripheral, let info = infoCharacteristic else { return }; inFlight = .readInfo; operationAt = ProcessInfo.processInfo.systemUptime; p.readValue(for: info) }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: if let p = peripheral, p.state == .connected, !ready { p.discoverServices([Self.serviceUUID]) } else { reconnect() }; if searchWanted { beginScan() }
        case .poweredOff: clearConnection(); scanning = false; status = stopWanted ? "Stop đang chờ · Bật Bluetooth để xóa liên kết" : "Thất bại · Bluetooth đang tắt"
        case .unauthorized: clearConnection(); status = "Thất bại · Chưa cấp quyền Bluetooth"
        case .unsupported: clearConnection(); status = "Thất bại · Thiết bị không hỗ trợ BLE"
        default: status = "Bluetooth chưa sẵn sàng"
        }
    }
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        for p in dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? [] { if wanted && p.identifier == rememberedID { peripheral = p; peripherals[p.identifier] = p; p.delegate = self; busy = true; connectedName = rememberedName; connectionAt = ProcessInfo.processInfo.systemUptime; if p.state == .connected { p.discoverServices([Self.serviceUUID]) } } else { central.cancelPeripheralConnection(p) } }
    }
    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""; guard Self.isTallyName(name) else { return }
        let received = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        if Self.validAdvertisement(received) { ownershipFrames[p.identifier] = received }
        let data = ownershipFrames[p.identifier]; let service = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.contains(Self.serviceUUID) ?? false
        guard service || Self.validAdvertisement(data) || peripherals[p.identifier] != nil else { return }; peripherals[p.identifier] = p
        let device = TallyDevice(id: p.identifier, name: name, rssi: RSSI.intValue, claimed: Self.claimedAdvertisement(data)); if let index = devices.firstIndex(where: { $0.id == p.identifier }) { devices[index] = device } else { devices.append(device) }; devices.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if stopWanted && awaitingLegacyRelease && p.identifier == rememberedID && Self.validAdvertisement(received) && !Self.claimedAdvertisement(received) { completeStop(); return }
        let management = Self.validAdvertisement(data) && Array(data!)[4] == 2
        if wanted && p.identifier == rememberedID && peripheral == nil && (!Self.inUseAdvertisement(data) || management) { attach(p) }
    }
    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) { guard p === peripheral && wanted else { central.cancelPeripheralConnection(p); return }; p.discoverServices([Self.serviceUUID]) }
    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { guard p === peripheral else { return }; clearConnection(); status = stopWanted ? "Stop đang chờ · Tìm lại \(rememberedName)" : "Thất bại · Đang nối lại \(rememberedName)"; afterDisconnect() }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) { guard p === peripheral else { return }; clearConnection(); status = stopWanted ? "Stop đang chờ · Tìm lại \(rememberedName)" : wanted ? "Standby · Chờ kết nối lại \(rememberedName)" : "Đã dừng · Chưa kết nối"; afterDisconnect() }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) { guard p === peripheral else { return }; guard error == nil, let service = p.services?.first(where: { $0.uuid == Self.serviceUUID }) else { fail("Không có dịch vụ LivePro Tally"); return }; p.discoverCharacteristics([Self.stateUUID,Self.authUUID,Self.ownerUUID,Self.releaseUUID,Self.infoUUID,Self.brightnessUUID], for: service) }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard p === peripheral else { return }
        guard error == nil, let state = service.characteristics?.first(where: { $0.uuid == Self.stateUUID }), let auth = service.characteristics?.first(where: { $0.uuid == Self.authUUID }), let owner = service.characteristics?.first(where: { $0.uuid == Self.ownerUUID }), let release = service.characteristics?.first(where: { $0.uuid == Self.releaseUUID }), state.properties.contains(.write), auth.properties.contains(.read), auth.properties.contains(.write) else { fail("Cần firmware LivePro Tally"); return }
        stateCharacteristic = state; authCharacteristic = auth; ownerCharacteristic = owner; releaseCharacteristic = release; infoCharacteristic = service.characteristics?.first(where: { $0.uuid == Self.infoUUID }); brightnessCharacteristic = service.characteristics?.first(where: { $0.uuid == Self.brightnessUUID && $0.properties.contains(.read) && $0.properties.contains(.write) }); brightnessAvailable = brightnessCharacteristic != nil
        if claimMode == 2 && infoCharacteristic == nil { forget(); status = "Thất bại · Cần firmware Tally 2.3 để chuyển thiết bị"; return }
        if stopWanted { claimMode = infoCharacteristic == nil ? 0 : 3 }
        authenticationStage = 0; status = stopWanted ? "Đang xác thực Stop · \(connectedName)" : "Đang xác thực · \(connectedName)"; inFlight = .claim; operationAt = ProcessInfo.processInfo.systemUptime; p.writeValue(Data([claimMode] + ownerToken), for: owner, type: .withResponse)
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard p === peripheral else { return }
        if characteristic.uuid == Self.brightnessUUID {
            guard case .readBrightness? = inFlight else { return }; inFlight = nil
            guard ready && !stopWanted else { pump(); return }
            guard error == nil, let data = characteristic.value, data.count == 2 else { brightnessWaiting = false; brightnessKnown = false; pendingBrightness = nil; brightnessStatus = "Thất bại · Không đọc được độ sáng"; return }
            let b = Array(data); guard (1...5).contains(Int(b[0])), b[1] <= 3 else { brightnessWaiting = false; brightnessKnown = false; pendingBrightness = nil; brightnessStatus = "Thất bại · Dữ liệu độ sáng không hợp lệ"; return }
            if b[1] == 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in guard let self = self, p === self.peripheral, self.ready && !self.stopWanted else { return }; self.brightnessReadNeeded = true; self.pump() }; return }
            brightnessLevel = Int(b[0]); brightnessKnown = b[1] != 3; let accepted = b[1] == 1 && (!brightnessWaiting || b[0] == writtenBrightness); brightnessWaiting = false
            if pendingBrightness == nil { brightnessSelection = brightnessLevel }
            brightnessStatus = accepted ? "Đã lưu · Mức \(brightnessLevel) / 5" : b[1] == 3 ? "Thất bại · Tally không cho phép chỉnh độ sáng" : "Thất bại · Chưa lưu được mức sáng"; pump(); return
        }
        if characteristic.uuid == Self.infoUUID {
            guard stopWanted && releaseReading else { return }; inFlight = nil
            guard error == nil, let data = characteristic.value, data.count == 4, data.first == 2 else { fail("Không đọc được xác nhận ESP32"); return }; let b = Array(data)
            if b[3] == 2 { completeStop("Đã dừng · Tally đang được thiết bị khác điều khiển"); return }; if b[2] == 1 { completeStop(); return }
            if b[2] == 2 { releaseReading = false; status = "Thất bại · ESP32 chưa xóa liên kết, đang thử Stop lại"; DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in guard let self = self, self.stopWanted, p === self.peripheral else { return }; self.releaseRequested = true; self.pump() }; return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in guard let self = self, p === self.peripheral, self.releaseReading else { return }; self.readInfo() }; return
        }
        if characteristic.uuid == Self.authUUID {
            guard error == nil, let data = characteristic.value else { fail("Không đọc được xác thực"); return }
            if data == Data([2]) { if stopWanted { completeStop() } else { forget(); status = "Liên kết đã reset · Search để chọn Tally" }; return }
            if data == Data([3]) { if stopWanted { completeStop("Đã dừng · Tally đang được thiết bị khác điều khiển") } else { let device = TallyDevice(id: p.identifier, name: rememberedName, rssi: 0, claimed: true); forget(); status = "Tally đã được chọn · Chọn khác hoặc chuyển thiết bị"; showOccupied(device) }; return }
            if authenticationStage == 0 { guard let response = Self.proof(data, token: ownerToken, mode: claimMode) else { fail("Firmware không tương thích"); return }; authenticationStage = 1; inFlight = .authentication; operationAt = ProcessInfo.processInfo.systemUptime; p.writeValue(response, for: characteristic, type: .withResponse) }
            else if authenticationStage == 2 && data == Data([0]) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in guard let self = self, p === self.peripheral, self.authenticationStage == 2 else { return }; p.readValue(for: characteristic) } }
            else if authenticationStage == 2 && data == Data([1]) { ready = true; busy = false; brightnessReadNeeded = brightnessAvailable && !stopWanted; brightnessKnown = false; retainConnectedDevice(); if stopWanted { status = "Đang Stop · Chờ xác nhận ESP32…"; releaseRequested = true } else { status = "Thành công · Đã kết nối \(connectedName)"; if let state = stateCharacteristic { p.setNotifyValue(true, for: state); p.readValue(for: state) } }; pendingState = desiredState; pump() }
            else { fail("Tally từ chối xác thực") }
        } else if characteristic.uuid == Self.stateUUID, error == nil, let data = characteristic.value, data.count == 1, let value = data.first, value <= 2 { accessoryState = value }
    }
    func peripheral(_ p: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard p === peripheral, let operation = inFlight else { return }
        switch operation { case .claim: guard characteristic.uuid == Self.ownerUUID else { return }; case .authentication: guard characteristic.uuid == Self.authUUID else { return }; case .release: guard characteristic.uuid == Self.releaseUUID else { return }; case .state: guard characteristic.uuid == Self.stateUUID else { return }; case .brightness: guard characteristic.uuid == Self.brightnessUUID else { return }; case .readBrightness, .readInfo: return }
        inFlight = nil; guard error == nil else { fail("Gửi dữ liệu lỗi"); return }
        switch operation {
        case .claim: if let auth = authCharacteristic { p.readValue(for: auth) }
        case .authentication: authenticationStage = 2; p.readValue(for: characteristic)
        case .release: if infoCharacteristic != nil { releaseReading = true; readInfo() } else { awaitingLegacyRelease = true; central?.cancelPeripheralConnection(p) }
        case .state(let value): accessoryState = value; pump()
        case .brightness: brightnessReadNeeded = true; pump()
        case .readBrightness, .readInfo: break
        }
    }
}
