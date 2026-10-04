import Foundation

enum TallyBLEProtocol {
    static let serviceUUID = "8f7a0001-7c3b-4a84-9c10-4e4154590001"
    static let stateUUID = "8f7a0002-7c3b-4a84-9c10-4e4154590001"
    static let configurationUUID = "8f7a0003-7c3b-4a84-9c10-4e4154590001"
    static func stateByte(_ tally: String, sessionHealthy: Bool) -> UInt8 {
        guard sessionHealthy else { return 0 }
        switch tally { case "program": return 1; case "preview": return 2; default: return 0 }
    }
    // Server ping/pong keeps an unchanged PROGRAM/PREVIEW alive.
    static func liveState(_ requested: UInt8, serverAge: TimeInterval) -> UInt8 {
        serverAge >= 0 && serverAge <= 4 && requested <= 2 ? requested : 0
    }
}

enum CrewRole: String, CaseIterable, Codable, Identifiable {
    case director = "DIRECTOR", camera = "CAMERA", tech = "TECH"
    case admin = "ADMIN"
    case production = "PRODUCTION", makeup = "MAKEUP", ac = "AC"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .admin: return "ADMIN"
        case .director: return "Đạo diễn"
        case .camera: return "Camera"
        case .tech: return "Kỹ thuật"
        case .production: return "Sản Xuất"
        case .makeup: return "Makeup"
        case .ac: return "AC"
        }
    }
}
struct JoinProfile: Codable, Equatable {
    var name = ""
    var room = "EVENT_A"
    var role: CrewRole = .camera
    var number = 1
    var cameraNumber = 1
    var roomTitle: String { "Sự kiện " + String(room.suffix(1)) }
    var deviceID: String { "\(room)_\(role.rawValue)_\(number)" }
    var validName: Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !n.isEmpty && n.unicodeScalars.count <= 40 && !n.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    var valid: Bool {
        role != .admin && validName && room.range(of: "^EVENT_[A-Z0-9]{1,32}$", options: .regularExpression) != nil && (1...300).contains(number)
        && (role != .camera || (1...30).contains(cameraNumber))
    }
    static let rooms = (65...74).map { "EVENT_" + String(UnicodeScalar($0)!) }
    func registration(clientID: String, password: String = "") -> [String: Any] {
        ["type": "register", "roomPassword": password, "protocolVersion": 4, "appVersion": "3.7.0", "clientType": "ios", "clientId": clientID,
         "deviceId": deviceID, "room": room, "role": role.rawValue,
         "number": number, "cameraNumber": role == .camera ? cameraNumber : 0,
         "name": name.trimmingCharacters(in: .whitespacesAndNewlines)]
    }
    func availability(clientID: String) -> [String: Any] {
        ["type": "availability", "protocolVersion": 4, "clientId": clientID, "room": room,
         "role": role.rawValue, "preferredNumber": number, "cameraNumber": cameraNumber]
    }
}
struct Member: Identifiable, Equatable {
    let id: String
    let name: String
    let role: CrewRole
    let number: Int
    let cameraNumber: Int
    init?(_ json: [String: Any]) {
        guard let id = json["deviceId"] as? String,
              let rawRole = json["role"] as? String, let role = CrewRole(rawValue: rawRole) else { return nil }
        self.id = id; self.role = role
        self.name = (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? ""
        self.number = (json["number"] as? Int) ?? 0
        self.cameraNumber = (json["cameraNumber"] as? Int) ?? 0
    }
    var roleTitle: String { role == .camera ? "Camera " + String(format: "%02d", cameraNumber) : role.title }
}
struct JSONLines {
    private var buffer = Data()
    mutating func append(_ data: Data) throws -> [[String: Any]] {
        buffer.append(data)
        guard buffer.count <= 262144 else { throw ProtocolError.frameTooLarge }
        var result: [[String: Any]] = []
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            if line.isEmpty { continue }
            guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw ProtocolError.invalidJSON }
            result.append(object)
        }
        return result
    }
}
enum ProtocolError: Error { case frameTooLarge, invalidJSON }
struct PCMFrames {
    private var pending = Data()
    mutating func append(_ data: Data) -> [Data] {
        pending.append(data)
        var frames: [Data] = []
        while pending.count >= 640 { frames.append(Data(pending.prefix(640))); pending.removeFirst(640) }
        return frames
    }
    mutating func clear() { pending.removeAll(keepingCapacity: true) }
}

// Backgrounding releases a held PTT, but leaves an explicitly latched mic active.
enum BackgroundMicPolicy {
    static func shouldRelease(active: Bool, latched: Bool) -> Bool { !active && !latched }
}

// Public endpoints only. SSH credentials never belong in client builds.
enum IntercomServer: String, CaseIterable, Identifiable {
    case hanoi, hochiminh
    var id: String { rawValue }
    var title: String { self == .hanoi ? "Server Hà Nội" : "Server Hồ Chí Minh" }
    var shortTitle: String { self == .hanoi ? "Hà Nội" : "Hồ Chí Minh" }
    var host: String { self == .hanoi ? "116.118.45.184" : "kailive1.ddns.net" }
}
