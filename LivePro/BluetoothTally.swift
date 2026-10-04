import Foundation
import Combine
import CoreBluetooth
import CryptoKit

struct TallyDevice: Identifiable { let id: UUID; var name: String; var rssi: Int }

final class BluetoothTally: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let serviceUUID = CBUUID(string: TallyBLEProtocol.serviceUUID)
    static let stateUUID = CBUUID(string: TallyBLEProtocol.stateUUID)
    static let authUUID = CBUUID(string: "8f7a0004-7c3b-4a84-9c10-4e4154590001")
    static let ownerUUID = CBUUID(string: "8f7a0005-7c3b-4a84-9c10-4e4154590001")
    static let releaseUUID = CBUUID(string: "8f7a0006-7c3b-4a84-9c10-4e4154590001")
    private static let key: [UInt8] = [0xf9,0x7d,0x62,0xb1,0x6e,0x41,0x25,0x8b,0x41,0xfd,0x1f,0xca,0x82,0xe7,0x54,0x23,0x8b,0xbe,0x74,0x88,0x19,0x94,0xc3,0x20,0x7e,0x5c,0x20,0x86,0x77,0x49,0xed,0xb5]
    @Published private(set) var devices: [TallyDevice] = []
    @Published private(set) var status = "Chưa kết nối"
    @Published private(set) var ready = false
    @Published private(set) var busy = false
    @Published private(set) var scanning = false
    @Published private(set) var connectedName = ""
    @Published private(set) var rememberedName: String
    @Published private(set) var accessoryState: UInt8 = 0
    private let defaults: UserDefaults
    private let ownerToken: [UInt8]
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var rememberedID: UUID?
    private var wanted: Bool
    private var nextDevice: TallyDevice?
    private var searchWanted = false
    private var stateCharacteristic: CBCharacteristic?
    private var authCharacteristic: CBCharacteristic?
    private var ownerCharacteristic: CBCharacteristic?
    private var releaseCharacteristic: CBCharacteristic?
    private var manualClaim = false
    private var releaseRequested = false
    private var requestedState: UInt8 = 0
    private var desiredState: UInt8 = 0
    private var lastServerMessage = -TimeInterval.infinity
    private var pendingState: UInt8?
    private enum Write { case claim, authentication, release, state(UInt8) }
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
        wanted = defaults.bool(forKey: "bleTallyAutoReconnect") && rememberedID != nil
        super.init()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.tick() }
        heartbeat = timer; timer.resume()
        if wanted { startCentral() }
    }
    deinit { heartbeat?.cancel(); retry?.cancel(); scanStop?.cancel() }
    static func stateByte(_ tally: String, sessionHealthy: Bool) -> UInt8 { TallyBLEProtocol.stateByte(tally, sessionHealthy: sessionHealthy) }
    static func isTallyName(_ value: String) -> Bool { value.lowercased().hasPrefix("tally") }
    static func proof(_ nonce: Data, token: [UInt8], manual: Bool) -> Data? {
        guard nonce.count == 16 && token.count == 16 else { return nil }
        var message = nonce; message.append(manual ? 1 : 0); message.append(contentsOf: token)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)).prefix(16))
    }
    func update(tally: String, sessionHealthy: Bool) { requestedState = Self.stateByte(tally, sessionHealthy: sessionHealthy); refreshState() }
    func serverMessageReceived() { lastServerMessage = ProcessInfo.processInfo.systemUptime; refreshState() }
    private func refreshState() {
        let value = TallyBLEProtocol.liveState(requestedState, serverAge: ProcessInfo.processInfo.systemUptime - lastServerMessage)
        if desiredState != value { desiredState = value; pendingState = value; pump() }
    }
    func sceneChanged(active: Bool) { if active && wanted { refreshState(); startCentral(); reconnect() } }
    func scan() { devices.removeAll(); retainConnectedDevice(); searchWanted = true; startCentral(); if central?.state == .poweredOn { beginScan() } }
    var connectedID: UUID? { ready ? peripheral?.identifier : nil }
    private func retainConnectedDevice() {
        guard ready, let p = peripheral else { return }
        if !devices.contains(where: { $0.id == p.identifier }) { devices.insert(TallyDevice(id: p.identifier, name: connectedName, rssi: 0), at: 0) }
    }
    func stopScan() { scanStop?.cancel(); scanStop = nil; searchWanted = false; scanning = false; central?.stopScan() }
    private func startCentral() {
        if central == nil { central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionRestoreIdentifierKey: "com.livepro.intercom.tally-central", CBCentralManagerOptionShowPowerAlertKey: true]) }
    }
    private func remember(_ device: TallyDevice) {
        rememberedID = device.id; rememberedName = device.name; wanted = true
        defaults.set(device.id.uuidString, forKey: "bleTallyID"); defaults.set(device.name, forKey: "bleTallyName"); defaults.set(true, forKey: "bleTallyAutoReconnect")
    }
    func connect(_ device: TallyDevice) {
        if peripheral?.identifier == device.id { if ready { status = "Thành công · Đã kết nối \(device.name)" }; return }
        guard peripherals[device.id] != nil else { return }
        stopScan(); retry?.cancel(); remember(device)
        if let old = peripheral { nextDevice = device; status = "Đang đổi Tally…"; if ready { releaseRequested = true; pump() } else { central?.cancelPeripheralConnection(old) } }
        else if let p = peripherals[device.id] { attach(p, manual: true) }
    }
    func reconnectRemembered() { guard rememberedID != nil else { return }; wanted = true; defaults.set(true, forKey: "bleTallyAutoReconnect"); startCentral(); reconnect() }
    func disconnect() {
        wanted = false; nextDevice = nil; retry?.cancel(); retry = nil; stopScan()
        rememberedID = nil; rememberedName = ""
        defaults.removeObject(forKey: "bleTallyID"); defaults.removeObject(forKey: "bleTallyName"); defaults.set(false, forKey: "bleTallyAutoReconnect")
        status = "Đã dừng · Chưa kết nối"
        if let p = peripheral { if ready { releaseRequested = true; pump() } else { central?.cancelPeripheralConnection(p) } }
        else { clearConnection() }
    }
    private func beginScan() {
        guard central?.state == .poweredOn else { return }
        central?.scanForPeripherals(withServices: [Self.serviceUUID], options: nil); scanning = true
        status = ready ? "Thành công · \(connectedName) · Đang Search" : "Đang Search…"
        if searchWanted {
            scanStop?.cancel()
            let work = DispatchWorkItem { [weak self] in guard let self = self else { return }; self.stopScan(); self.status = self.ready ? "Thành công · Đã kết nối \(self.connectedName)" : self.devices.isEmpty ? "Không tìm thấy Tally" : "Chọn Tally để kết nối" }
            scanStop = work; DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
        }
    }
    private func reconnect() {
        guard wanted, peripheral == nil, let id = rememberedID, let central = central, central.state == .poweredOn else { return }
        if let p = central.retrievePeripherals(withIdentifiers: [id]).first { attach(p) } else { beginScan() }
    }
    private func attach(_ p: CBPeripheral, manual: Bool = false) {
        guard peripheral == nil, central?.state == .poweredOn else { return }
        central?.stopScan(); scanning = false; retry?.cancel(); peripheral = p; peripherals[p.identifier] = p; p.delegate = self
        busy = true; ready = false; connectedName = rememberedName; connectionAt = ProcessInfo.processInfo.systemUptime
        manualClaim = manual
        status = "Đang kết nối · \(connectedName)"
        if p.state == .connected { p.discoverServices([Self.serviceUUID]) } else { central?.connect(p, options: nil) }
    }
    private func clearConnection() {
        ready = false; busy = false; peripheral = nil; stateCharacteristic = nil; authCharacteristic = nil; ownerCharacteristic = nil; releaseCharacteristic = nil; releaseRequested = false; inFlight = nil; pendingState = nil; accessoryState = 0; connectedName = ""; authenticationStage = 0
    }
    private func afterDisconnect() {
        if let device = nextDevice { nextDevice = nil; if let p = peripherals[device.id] { attach(p, manual: true); return } }
        if wanted { let work = DispatchWorkItem { [weak self] in self?.reconnect() }; retry = work; DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work) }
    }
    private func fail(_ message: String) { status = "Thất bại · \(message)"; if let p = peripheral { central?.cancelPeripheralConnection(p) } }
    private func tick() {
        refreshState(); let now = ProcessInfo.processInfo.systemUptime
        if peripheral != nil && !ready && now - connectionAt > 12 { fail("Không kết nối được \(rememberedName)"); return }
        if inFlight != nil && now - operationAt > 3.5 { fail("Tally không phản hồi"); return }
        if ready && wanted { pendingState = desiredState; pump() }
    }
    private func pump() {
        if releaseRequested && ready && inFlight == nil, let p = peripheral, let release = releaseCharacteristic {
            releaseRequested = false; inFlight = .release; operationAt = ProcessInfo.processInfo.systemUptime; p.writeValue(Data([1]), for: release, type: .withResponse); return
        }
        guard wanted, ready, inFlight == nil, let value = pendingState, let p = peripheral, let state = stateCharacteristic else { return }
        pendingState = nil; inFlight = .state(value); operationAt = ProcessInfo.processInfo.systemUptime
        p.writeValue(Data([value]), for: state, type: .withResponse)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: if let p = peripheral, p.state == .connected, !ready { p.discoverServices([Self.serviceUUID]) } else { reconnect() }; if searchWanted { beginScan() }
        case .poweredOff: clearConnection(); scanning = false; status = "Thất bại · Bluetooth đang tắt"
        case .unauthorized: clearConnection(); status = "Thất bại · Chưa cấp quyền Bluetooth"
        case .unsupported: clearConnection(); status = "Thất bại · Thiết bị không hỗ trợ BLE"
        default: status = "Bluetooth chưa sẵn sàng"
        }
    }
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        for p in dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? [] {
            if wanted && p.identifier == rememberedID { peripheral = p; peripherals[p.identifier] = p; p.delegate = self; busy = true; connectedName = rememberedName; connectionAt = ProcessInfo.processInfo.systemUptime; if p.state == .connected { p.discoverServices([Self.serviceUUID]) } }
            else { central.cancelPeripheralConnection(p) }
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
        guard Self.isTallyName(name) else { return }; peripherals[p.identifier] = p
        let device = TallyDevice(id: p.identifier, name: name, rssi: RSSI.intValue)
        if let index = devices.firstIndex(where: { $0.id == p.identifier }) { devices[index] = device } else { devices.append(device) }
        devices.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if wanted && p.identifier == rememberedID && peripheral == nil { attach(p) }
    }
    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) { guard p === peripheral && wanted else { central.cancelPeripheralConnection(p); return }; p.discoverServices([Self.serviceUUID]) }
    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { guard p === peripheral else { return }; clearConnection(); status = wanted ? "Thất bại · Đang nối lại \(rememberedName)" : "Đã dừng · Chưa kết nối"; afterDisconnect() }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) { guard p === peripheral else { return }; clearConnection(); status = wanted ? "Standby · Chờ kết nối lại \(rememberedName)" : "Đã dừng · Chưa kết nối"; afterDisconnect() }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard p === peripheral else { return }; guard error == nil, let service = p.services?.first(where: { $0.uuid == Self.serviceUUID }) else { fail("Không có dịch vụ LivePro Tally"); return }
        p.discoverCharacteristics([Self.stateUUID,Self.authUUID,Self.ownerUUID,Self.releaseUUID], for: service)
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard p === peripheral else { return }
        guard error == nil, let state = service.characteristics?.first(where: { $0.uuid == Self.stateUUID }), let auth = service.characteristics?.first(where: { $0.uuid == Self.authUUID }), let owner = service.characteristics?.first(where: { $0.uuid == Self.ownerUUID }), let release = service.characteristics?.first(where: { $0.uuid == Self.releaseUUID }), state.properties.contains(.write), auth.properties.contains(.read), auth.properties.contains(.write) else { fail("Cần firmware Tally 2.1"); return }
        stateCharacteristic = state; authCharacteristic = auth; ownerCharacteristic = owner; releaseCharacteristic = release; authenticationStage = 0; status = "Đang xác thực · \(connectedName)"
        inFlight = .claim; operationAt = ProcessInfo.processInfo.systemUptime; p.writeValue(Data([manualClaim ? UInt8(1) : UInt8(0)] + ownerToken), for: owner, type: .withResponse)
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard p === peripheral else { return }
        if characteristic.uuid == Self.authUUID {
            guard error == nil, let data = characteristic.value else { fail("Không đọc được xác thực"); return }
            if data == Data([2]) { disconnect(); status = "Liên kết đã reset · Search để chọn Tally"; return }
            if data == Data([3]) { fail("Tally đang nhớ thiết bị khác"); return }
            if authenticationStage == 0 {
                guard let response = Self.proof(data, token: ownerToken, manual: manualClaim) else { fail("Firmware không tương thích"); return }
                authenticationStage = 1; inFlight = .authentication; operationAt = ProcessInfo.processInfo.systemUptime; p.writeValue(response, for: characteristic, type: .withResponse)
            } else if authenticationStage == 2 && data == Data([0]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in guard let self = self, p === self.peripheral, self.authenticationStage == 2 else { return }; p.readValue(for: characteristic) }
            } else if authenticationStage == 2 && data == Data([1]) {
                ready = true; busy = false; retainConnectedDevice(); status = "Thành công · Đã kết nối \(connectedName)"
                if let state = stateCharacteristic { p.setNotifyValue(true, for: state); p.readValue(for: state) }
                pendingState = desiredState; pump()
            } else { fail("Tally từ chối xác thực") }
        } else if characteristic.uuid == Self.stateUUID, error == nil, let data = characteristic.value, data.count == 1, let value = data.first, value <= 2 { accessoryState = value }
    }
    func peripheral(_ p: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard p === peripheral, let operation = inFlight else { return }
        switch operation { case .claim: guard characteristic.uuid == Self.ownerUUID else { return }; case .authentication: guard characteristic.uuid == Self.authUUID else { return }; case .release: guard characteristic.uuid == Self.releaseUUID else { return }; case .state: guard characteristic.uuid == Self.stateUUID else { return } }
        inFlight = nil; guard error == nil else { fail("Gửi dữ liệu lỗi"); return }
        switch operation {
        case .claim: if let auth = authCharacteristic { p.readValue(for: auth) }
        case .authentication: authenticationStage = 2; p.readValue(for: characteristic)
        case .release: ready = false; central?.cancelPeripheralConnection(p)
        case .state(let value): accessoryState = value; pump()
        }
    }
}
