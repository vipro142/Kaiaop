import Foundation
import AVFoundation

final class VoiceAudio {
    var onNeedsRecovery: ((String) -> Void)?
    private var configurationObserver: NSObjectProtocol?
    private var recoveryIssued = false
    private var silentIntervals = 0
    private var compatibilityMode = false
    private var playedFrames = 0
    private var stalledPlaybackIntervals = 0
    var onDiagnostic: ((String) -> Void)?
    private var captureWatchdog: Timer?
    private var inputBuffers = 0
    private var outputFrames = 0
    var onLevel: ((Double) -> Void)?
    var onPCM: ((Data) -> Void)?
    private var engine: AVAudioEngine?
    private var tapInstalled = false
    private var player: AVAudioPlayerNode?
    private let lock = NSLock()
    private var transmitting = false
    private var epoch = 0
    private var packets = PCMFrames()
    private var queuedBuffers = 0
    private var playbackEpoch = 0
    private let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)!
    private let playFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    var volume: Float = 0.75 { didSet { player?.volume = volume } }
    var speaker = true
    var running: Bool { engine?.isRunning == true }

    func start() throws {
        if running { return }
        stop(deactivate: false)
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [.allowBluetooth]
        if speaker { options.insert(.defaultToSpeaker) }
        try session.setCategory(.playAndRecord, mode: compatibilityMode ? .default : .voiceChat, options: options)
        try session.setPreferredSampleRate(48000)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)
        let engine = AVAudioEngine(), player = AVAudioPlayerNode()
        self.engine = engine; self.player = player
        do {
            // Voice processing uses the output path as the echo reference.
            if !compatibilityMode { try engine.inputNode.setVoiceProcessingEnabled(true) }
            let inputFormat = engine.inputNode.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
                  let converter = AVAudioConverter(from: inputFormat, to: pcmFormat) else {
                throw NSError(domain: "LIVEPRO.Audio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không có microphone khả dụng"])
            }
            engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: playFormat)
            player.volume = volume
            var converterEpoch = -1
            var lastMeterTime = 0.0
            engine.inputNode.installTap(onBus: 0, bufferSize: 960, format: inputFormat) { [weak self] buffer, _ in
                guard let self = self else { return }
                self.lock.lock(); let enabled = self.transmitting, token = self.epoch; self.lock.unlock()
                self.lock.lock(); self.inputBuffers += 1; self.lock.unlock()
                guard enabled else { return }
                // Meter the input directly, independent of resampling/network packet production.
                let meterNow = ProcessInfo.processInfo.systemUptime
                if meterNow - lastMeterTime >= 0.05, buffer.frameLength > 0 {
                    lastMeterTime = meterNow
                    let count = Int(buffer.frameLength)
                    let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
                    var energy = 0.0
                    if let samples = buffer.floatChannelData?[0] {
                        for i in 0..<count { let v = Double(samples[i * stride]); energy += v * v }
                    } else if let samples = buffer.int16ChannelData?[0] {
                        for i in 0..<count { let v = Double(samples[i * stride]) / 32768; energy += v * v }
                    }
                    let rms = sqrt(energy / Double(count))
                    let level = max(0, min(1, (20 * log10(max(rms, 0.000001)) + 72) / 60))
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.lock.lock(); let current = self.transmitting && self.epoch == token; self.lock.unlock()
                        if current { self.onLevel?(level) }
                    }
                }
                if converterEpoch != token { converter.reset(); converterEpoch = token }
                let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / inputFormat.sampleRate) + 32)
                guard let output = AVAudioPCMBuffer(pcmFormat: self.pcmFormat, frameCapacity: capacity) else { return }
                var supplied = false, error: NSError?
                let status = converter.convert(to: output, error: &error) { _, state in
                    if supplied { state.pointee = .noDataNow; return nil }
                    supplied = true; state.pointee = .haveData; return buffer
                }
                guard status != .error, error == nil, let samples = output.int16ChannelData?[0], output.frameLength > 0 else { return }
                let bytes = Data(bytes: samples, count: Int(output.frameLength) * 2)
                self.lock.lock()
                guard self.transmitting, self.epoch == token else { self.lock.unlock(); return }
                let frames = self.packets.append(bytes); self.outputFrames += frames.count; self.lock.unlock()
                for frame in frames {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.lock.lock(); let current = self.transmitting && self.epoch == token; self.lock.unlock()
                        if current { self.onPCM?(frame) }
                    }
                }
            }
            tapInstalled = true
            recoveryIssued = false; silentIntervals = 0; playedFrames = 0; stalledPlaybackIntervals = 0
            configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self, weak engine] _ in
                // Never tear down an engine inside its configuration notification callback.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak engine] in
                    guard let self = self, let changed = engine, self.engine === changed else { return }
                    self.requestRecovery("Cấu hình micro/loa đã thay đổi", fallback: false)
                }
            }
            engine.prepare(); try engine.start(); player.play()
            captureWatchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.lock.lock(); let enabled = self.transmitting, buffers = self.inputBuffers, frames = self.outputFrames
                self.inputBuffers = 0; self.outputFrames = 0; self.lock.unlock()
                let source = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? "Không có đầu vào"
                let destination = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "Không có loa"
                let played = self.playedFrames; self.playedFrames = 0
                let state = self.running ? "RUN" : "STOP"
                let mode = self.compatibilityMode ? "Dự phòng" : "Voice"
                self.onDiagnostic?("\(state) · \(mode) · \(source) → \(destination)\nThu \(buffers)/s · PCM \(frames)/s · Phát \(played)/s")
                self.silentIntervals = buffers == 0 ? self.silentIntervals + 1 : 0
                self.stalledPlaybackIntervals = self.queuedBuffers >= 6 && played == 0 ? self.stalledPlaybackIntervals + 1 : 0
                if !self.running || self.silentIntervals >= 3 || self.stalledPlaybackIntervals >= 3 {
                    self.requestRecovery(enabled ? "Micro không trả dữ liệu" : "Đường âm thanh chưa hoạt động", fallback: true)
                }
            }
        } catch { stop(); throw error }
    }
    private func requestRecovery(_ reason: String, fallback: Bool) {
        guard !recoveryIssued else { return }
        recoveryIssued = true
        if fallback { compatibilityMode = true }
        onNeedsRecovery?(reason)
    }
    func setTransmitting(_ enabled: Bool) {
        lock.lock(); guard transmitting != enabled else { lock.unlock(); return }; epoch += 1; transmitting = enabled; packets.clear(); inputBuffers = 0; outputFrames = 0; lock.unlock()
        if !enabled { onLevel?(0) }
    }
    func play(_ pcm: Data) {
        guard pcm.count == 640, running, let player = player, queuedBuffers < 6,
              let buffer = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: 320),
              let samples = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = 320
        let bytes = [UInt8](pcm)
        for i in 0..<320 {
            let bits = UInt16(bytes[i * 2]) | (UInt16(bytes[i * 2 + 1]) << 8)
            samples[i] = Float(Int16(bitPattern: bits)) / 32768
        }
        queuedBuffers += 1; let token = playbackEpoch
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, token == self.playbackEpoch else { return }
                self.queuedBuffers = max(0, self.queuedBuffers - 1); self.playedFrames += 1
            }
        }
    }
    func flushPlayback() {
        playbackEpoch += 1; queuedBuffers = 0; player?.stop()
        if running { player?.play() }
    }
    func stop(deactivate: Bool = true) {
        if let observer = configurationObserver { NotificationCenter.default.removeObserver(observer); configurationObserver = nil }
        captureWatchdog?.invalidate(); captureWatchdog = nil
        setTransmitting(false); playbackEpoch += 1; queuedBuffers = 0
        if let engine = engine { if tapInstalled { engine.inputNode.removeTap(onBus: 0) }; engine.stop() }
        tapInstalled = false
        player?.stop(); engine = nil; player = nil
        if deactivate { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
}
