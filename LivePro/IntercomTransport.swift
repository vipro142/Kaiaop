import Foundation
import Network

// All state and callbacks run on the main queue. Microphone frames cross onto it explicitly.
final class IntercomTransport {
    var onSendError: ((String) -> Void)?
    var onMessage: (([String: Any]) -> Void)?
    var onConnection: ((String) -> Void)?
    var onAudio: ((Data) -> Void)?
    var onTraffic: ((Int, Int) -> Void)?
    private var host: NWEndpoint.Host = "116.118.45.184"
    private let clientID: String
    private var tcp: NWConnection?
    private var udp: NWConnection?
    private var heartbeat: Timer?
    private var retry: DispatchWorkItem?
    private var grantDeadline: DispatchWorkItem?
    private var tcpDeadline: DispatchWorkItem?
    private var lines = JSONLines()
    private var profile: JoinProfile?
    private var roomPassword = ""
    private var generation = 0
    private var lastReply = Date()
    private var registered = false
    private var ready = false
    private var wanted = false
    private var held = false
    private var granted = false
    private var id = ""
    private var tx = 0, rx = 0
    private var queries: [UUID: NWConnection] = [:]
    init(clientID: String) { self.clientID = clientID }

    func selectServer(_ server: IntercomServer) {
        leave()
        host = NWEndpoint.Host(server.host)
    }
    func availability(_ profile: JoinProfile, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        let key = UUID(), connection = NWConnection(host: host, port: 6000, using: .tcp)
        queries[key] = connection
        var parser = JSONLines(), done = false
        let finish: (Result<[String: Any], Error>) -> Void = { [weak self] result in
            guard !done else { return }; done = true
            connection.stateUpdateHandler = nil; connection.cancel(); self?.queries.removeValue(forKey: key)
            completion(result)
        }
        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, complete, error in
                guard !done else { return }
                if let error = error { finish(.failure(error)); return }
                do {
                    if let data = data, let response = try parser.append(data).first { finish(.success(response)); return }
                    if complete { finish(.failure(ProtocolError.invalidJSON)) } else { receive() }
                } catch { finish(.failure(error)) }
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Self.send(profile.availability(clientID: self.clientID), through: connection)
                receive()
            case .failed(let error): finish(.failure(error))
            default: break
            }
        }
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if !done { finish(.failure(NSError(domain: "LIVEPRO", code: 1, userInfo: [NSLocalizedDescriptionKey: "Hết thời gian kết nối máy chủ"]))) } }
    }
    func join(_ value: JoinProfile, password: String = "") {
        leave(); roomPassword = password; profile = value; wanted = true; tx = 0; rx = 0; connect()
    }
    private func connect() {
        generation += 1; let token = generation
        lines = JSONLines(); held = false; granted = false; ready = false; registered = false
        onConnection?("connecting")
        guard let profile = profile else { return }
        let connection = NWConnection(host: host, port: 6000, using: .tcp); tcp = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self, token == self.generation else { return }
            switch state {
            case .ready:
                self.lastReply = Date()
                Self.send(profile.registration(clientID: self.clientID, password: self.roomPassword), through: connection)
                self.receiveTCP(token)
                self.heartbeat = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    guard let self = self, token == self.generation else { return }
                    if Date().timeIntervalSince(self.lastReply) > 15 { self.disconnect(token); return }
                    self.command("ping"); self.registerUDP(); self.onTraffic?(self.tx, self.rx)
                }
            case .failed: self.disconnect(token)
            default: break
            }
        }
        connection.start(queue: .main)
        let deadline = DispatchWorkItem { [weak self] in
            guard let self = self, token == self.generation, !self.ready else { return }
            self.disconnect(token)
        }
        tcpDeadline = deadline; DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: deadline)
    }
    private func receiveTCP(_ token: Int) {
        tcp?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self = self, token == self.generation else { return }
            if error != nil { self.disconnect(token); return }
            do {
                if let data = data {
                    self.lastReply = Date()
                    for message in try self.lines.append(data) { self.handle(message, token: token) }
                }
            } catch { self.disconnect(token); return }
            guard token == self.generation else { return }
            if complete { self.disconnect(token) } else { self.receiveTCP(token) }
        }
    }
    private func handle(_ message: [String: Any], token: Int) {
        switch message["type"] as? String {
        case "registered":
            registered = true; id = (message["deviceId"] as? String) ?? ""
            if let number = message["number"] as? Int { profile?.number = number }
            udp?.cancel()
            let connection = NWConnection(host: host, port: 6001, using: .udp); udp = connection
            connection.stateUpdateHandler = { [weak self] state in
                guard let self = self, token == self.generation else { return }
                switch state {
                case .ready: self.registerUDP(); self.receiveUDP(token)
                case .failed: self.disconnect(token)
                default: break
                }
            }
            connection.start(queue: .main)
        case "ptt_granted":
            grantDeadline?.cancel()
            if ready && held { granted = true } else { command("ptt_stop") }
        case "ptt_released", "ptt_busy", "ptt_revoked": granted = false
        case "kicked": leave()
        case "error":
            if !registered { wanted = false }
        default: break
        }
        onMessage?(message)
    }
    private func receiveUDP(_ token: Int) {
        udp?.receiveMessage { [weak self] data, _, _, error in
            guard let self = self, token == self.generation else { return }
            if error != nil { self.disconnect(token); return }
            if let data = data {
                if data == Data("UDP_OK".utf8) {
                    if !self.ready { self.ready = true; self.tcpDeadline?.cancel(); self.onConnection?("ready") }
                } else if data.count == 640 { self.rx += data.count; self.onAudio?(data) }
            }
            self.receiveUDP(token)
        }
    }
    private func registerUDP() {
        guard registered, let udp = udp, case .ready = udp.state else { return }
        udp.send(content: Data("REGISTER|\(id)".utf8), completion: .contentProcessed({ _ in }))
    }
    func microphone(_ on: Bool) {
        if !on { held = false; granted = false; grantDeadline?.cancel(); if registered { command("ptt_stop") }; return }
        guard ready, !held else { return }; held = true; command("ptt_start")
        let token = generation
        let deadline = DispatchWorkItem { [weak self] in
            guard let self = self, self.generation == token, self.held, !self.granted else { return }
            self.disconnect(token)
        }
        grantDeadline = deadline; DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: deadline)
    }
    func audio(_ data: Data) {
        guard ready, granted, held, data.count == 640 else { return }
        var packet = Data("AUDIO|\(id)|".utf8); packet.append(data)
        let token = generation
        udp?.send(content: packet, completion: .contentProcessed({ [weak self] error in
            guard let self = self, self.generation == token else { return }
            if let error = error { self.onSendError?("Lỗi gửi âm thanh: \(error.localizedDescription)"); self.disconnect(token) }
            else { self.tx += packet.count }
        }))
    }
    private func command(_ type: String) { Self.send(["type": type], through: tcp) }
    private static func send(_ message: [String: Any], through connection: NWConnection?) {
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(10); connection?.send(content: data, completion: .contentProcessed({ _ in }))
    }
    private func disconnect(_ token: Int) {
        guard token == generation else { return }
        cleanup(); onConnection?("offline")
        guard wanted else { return }
        let expected = generation
        let task = DispatchWorkItem { [weak self] in
            guard let self = self, self.wanted, self.generation == expected else { return }; self.connect()
        }
        retry = task; DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: task)
    }
    private func cleanup() {
        generation += 1; heartbeat?.invalidate(); heartbeat = nil; retry?.cancel()
        tcpDeadline?.cancel(); grantDeadline?.cancel()
        tcp?.stateUpdateHandler = nil; tcp?.cancel(); tcp = nil
        udp?.stateUpdateHandler = nil; udp?.cancel(); udp = nil
        ready = false; registered = false; held = false; granted = false
    }
    func leave() { roomPassword = ""; wanted = false; microphone(false); cleanup() }
}
