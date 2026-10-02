import Foundation
import AVFoundation
import AudioToolbox

// Lifecycle and public methods run on main. Audio Queue callbacks use lock;
// they never call stop/dispose or UI code synchronously.
final class VoiceAudio {
    var onNeedsRecovery: ((String) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var onLevel: ((Double) -> Void)?
    var onPCM: ((Data) -> Void)?
    private let lock = NSLock()
    private var inputQueue: AudioQueueRef?
    private var outputQueue: AudioQueueRef?
    private var active = false
    private var transmitting = false
    private var epoch = 0
    private var packets = PCMFrames()
    private var pendingPlayback: [Data] = []
    private var inputBuffers = 0, outputTicks = 0, outputFrames = 0, playedFrames = 0
    private var callbackFailure: String?
    private var watchdog: Timer?
    private var emptyInputSeconds = 0, emptyOutputSeconds = 0
    private var failureReported = false
    private var lastMeterTime = 0.0
    var speaker = true
    var volume: Float = 0.75 {
        didSet {
            if let queue = outputQueue {
                let status = AudioQueueSetParameter(queue, kAudioQueueParam_Volume, max(0, min(1, volume)))
                if status != noErr { reportFailure(Self.errorText("Âm lượng loa", status)) }
            }
        }
    }
    var running: Bool {
        lock.lock(); defer { lock.unlock() }
        return active
    }
    private static var format: AudioStreamBasicDescription {
        AudioStreamBasicDescription(mSampleRate: 16000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
    }
    private static func errorText(_ step: String, _ status: OSStatus) -> String {
        "\(step): OSStatus \(status)"
    }
    private func check(_ status: OSStatus, _ step: String) throws {
        if status != noErr {
            throw NSError(domain: "LIVEPRO.AudioQueue", code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: Self.errorText(step, status)])
        }
    }
    func start() throws {
        if running { return }
        stop(deactivate: false)
        failureReported = false
        emptyInputSeconds = 0; emptyOutputSeconds = 0
        do {
            let session = AVAudioSession.sharedInstance()
            guard session.recordPermission == .granted else {
                throw NSError(domain: "LIVEPRO.AudioQueue", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "iOS chưa cấp quyền Microphone cho LIVEPRO."])
            }
            var options: AVAudioSession.CategoryOptions = [.allowBluetooth]
            if speaker { options.insert(.defaultToSpeaker) }
            try session.setCategory(.playAndRecord, mode: .default, options: options)
            try? session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true)
            // Use the system route, including a wired/Bluetooth microphone when selected.
            // No hardware sample-rate/channel assumptions: queues convert the PCM stream.
            let context = Unmanaged.passUnretained(self).toOpaque()
            var format = Self.format
            var createdInput: AudioQueueRef?
            let inputStatus = AudioQueueNewInput(&format, { context, queue, buffer, _, _, _ in
                guard let context = context else { return }
                Unmanaged<VoiceAudio>.fromOpaque(context).takeUnretainedValue().capture(queue, buffer)
            }, context, nil, nil, 0, &createdInput)
            inputQueue = createdInput
            try check(inputStatus, "Tạo đường thu micro")
            guard let input = createdInput else { try check(-1, "Micro không trả queue"); return }

            var createdOutput: AudioQueueRef?
            let outputStatus = AudioQueueNewOutput(&format, { context, queue, buffer in
                guard let context = context else { return }
                Unmanaged<VoiceAudio>.fromOpaque(context).takeUnretainedValue().render(queue, buffer)
            }, context, nil, nil, 0, &createdOutput)
            outputQueue = createdOutput
            try check(outputStatus, "Tạo đường phát loa")
            guard let output = createdOutput else { try check(-1, "Loa không trả queue"); return }
            try check(AudioQueueSetParameter(output, kAudioQueueParam_Volume, max(0, min(1, volume))), "Đặt âm lượng")

            // Three 20ms buffers in each direction. Output keeps rendering silence
            // between network packets, so receiving does not depend on starting PTT.
            for _ in 0..<3 {
                var buffer: AudioQueueBufferRef?
                try check(AudioQueueAllocateBuffer(input, 640, &buffer), "Cấp buffer micro")
                guard let buffer = buffer else { try check(-1, "Buffer micro rỗng"); return }
                try check(AudioQueueEnqueueBuffer(input, buffer, 0, nil), "Nạp buffer micro")
            }
            for _ in 0..<3 {
                var buffer: AudioQueueBufferRef?
                try check(AudioQueueAllocateBuffer(output, 640, &buffer), "Cấp buffer loa")
                guard let buffer = buffer else { try check(-1, "Buffer loa rỗng"); return }
                memset(buffer.pointee.mAudioData, 0, 640)
                buffer.pointee.mAudioDataByteSize = 640
                buffer.pointee.mUserData = nil
                try check(AudioQueueEnqueueBuffer(output, buffer, 0, nil), "Nạp buffer loa")
            }
            lock.lock(); active = true; lock.unlock()
            try check(AudioQueueStart(output, nil), "Khởi động loa")
            try check(AudioQueueStart(input, nil), "Khởi động micro")
            watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateDiagnostic() }
            onDiagnostic?("Audio Queue · Đang chờ dữ liệu micro/loa…")
        } catch {
            stop()
            onDiagnostic?("Audio STOP · " + error.localizedDescription)
            throw error
        }
    }
    private func capture(_ queue: AudioQueueRef, _ buffer: AudioQueueBufferRef) {
        lock.lock()
        guard active, inputQueue == queue else { lock.unlock(); return }
        let count = Int(buffer.pointee.mAudioDataByteSize)
        let token = epoch
        var frames: [Data] = []
        var level: Double?
        if count > 0 {
            inputBuffers += 1
            if transmitting {
                let data = Data(bytes: buffer.pointee.mAudioData, count: count)
                frames = packets.append(data); outputFrames += frames.count
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastMeterTime >= 0.05, count >= 2 {
                    lastMeterTime = now
                    let samples = buffer.pointee.mAudioData.assumingMemoryBound(to: Int16.self)
                    var energy = 0.0
                    for i in 0..<(count / 2) { let v = Double(samples[i]) / 32768; energy += v * v }
                    let rms = sqrt(energy / Double(count / 2))
                    level = max(0, min(1, (20 * log10(max(rms, 0.000001)) + 72) / 60))
                }
            }
        }
        let status = AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
        if status != noErr { callbackFailure = Self.errorText("Nạp lại buffer micro", status) }
        lock.unlock()
        guard !frames.isEmpty || level != nil else { return }
        let capturedFrames = frames, capturedLevel = level
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock(); let valid = self.active && self.transmitting && self.epoch == token; self.lock.unlock()
            guard valid else { return }
            if let level = capturedLevel { self.onLevel?(level) }
            for frame in capturedFrames { self.onPCM?(frame) }
        }
    }
    private func render(_ queue: AudioQueueRef, _ buffer: AudioQueueBufferRef) {
        lock.lock(); defer { lock.unlock() }
        guard active, outputQueue == queue else { return }
        outputTicks += 1
        // Queue callback means reusable, not proof the physical speaker was audible.
        if buffer.pointee.mUserData != nil { playedFrames += 1 }
        if !pendingPlayback.isEmpty {
            let frame = pendingPlayback.removeFirst()
            frame.withUnsafeBytes { raw in
                if let address = raw.baseAddress { memcpy(buffer.pointee.mAudioData, address, 640) }
            }
            buffer.pointee.mUserData = UnsafeMutableRawPointer(bitPattern: 1)
        } else {
            memset(buffer.pointee.mAudioData, 0, 640)
            buffer.pointee.mUserData = nil
        }
        buffer.pointee.mAudioDataByteSize = 640
        let status = AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
        if status != noErr { callbackFailure = Self.errorText("Nạp lại buffer loa", status) }
    }
    func setTransmitting(_ enabled: Bool) {
        lock.lock()
        if transmitting != enabled { epoch += 1; transmitting = enabled; packets.clear() }
        lock.unlock()
        if !enabled { onLevel?(0) }
    }
    func play(_ pcm: Data) {
        guard pcm.count == 640 else { return }
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        if pendingPlayback.count >= 6 { pendingPlayback.removeFirst() }
        pendingPlayback.append(pcm)
    }
    func flushPlayback() {
        lock.lock(); pendingPlayback.removeAll(); lock.unlock()
        // At most three already submitted 20ms buffers remain; stop() disposes immediately.
    }
    private func updateDiagnostic() {
        lock.lock()
        let captured = inputBuffers, pcm = outputFrames, ticks = outputTicks, played = playedFrames
        let failure = callbackFailure
        inputBuffers = 0; outputFrames = 0; outputTicks = 0; playedFrames = 0
        lock.unlock()
        let session = AVAudioSession.sharedInstance()
        let input = session.currentRoute.inputs.map { $0.portName }.joined(separator: ", ")
        let output = session.currentRoute.outputs.map { $0.portName }.joined(separator: ", ")
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "unknown"
        onDiagnostic?("v\(version) · Audio Queue · \(input) → \(output)\nThu \(captured)/s · PCM \(pcm)/s · Loa \(ticks)/s · Nhận phát \(played)/s")
        emptyInputSeconds = captured == 0 ? emptyInputSeconds + 1 : 0
        emptyOutputSeconds = ticks == 0 ? emptyOutputSeconds + 1 : 0
        if let failure = failure { reportFailure(failure) }
        else if emptyInputSeconds >= 5 || emptyOutputSeconds >= 5 {
            reportFailure("Audio Queue không có callback trong 5s: micro=\(captured)/s, loa=\(ticks)/s; input=[\(input)], output=[\(output)]")
        }
    }
    private func reportFailure(_ reason: String) {
        guard !failureReported else { return }
        failureReported = true
        onNeedsRecovery?(reason)
    }
    func stop(deactivate: Bool = true) {
        watchdog?.invalidate(); watchdog = nil
        lock.lock()
        active = false; transmitting = false; epoch += 1
        let input = inputQueue, output = outputQueue
        inputQueue = nil; outputQueue = nil
        pendingPlayback.removeAll(); packets.clear()
        callbackFailure = nil
        inputBuffers = 0; outputFrames = 0; outputTicks = 0; playedFrames = 0
        lock.unlock()
        // Dispose waits for callback completion; never hold lock while disposing.
        if let input = input { AudioQueueStop(input, true); AudioQueueDispose(input, true) }
        if let output = output { AudioQueueStop(output, true); AudioQueueDispose(output, true) }
        onLevel?(0)
        if deactivate { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
    deinit { stop() }
}
