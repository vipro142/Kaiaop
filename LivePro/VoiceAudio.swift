import Foundation
import AVFoundation

final class VoiceAudio {
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
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
        try session.setPreferredSampleRate(48000)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)
        let engine = AVAudioEngine(), player = AVAudioPlayerNode()
        self.engine = engine; self.player = player
        do {
            // Voice processing uses the output path as the echo reference.
            try engine.inputNode.setVoiceProcessingEnabled(true)
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
                guard enabled else { return }
                if converterEpoch != token { converter.reset(); converterEpoch = token }
                let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / inputFormat.sampleRate) + 32)
                guard let output = AVAudioPCMBuffer(pcmFormat: self.pcmFormat, frameCapacity: capacity) else { return }
                var supplied = false, error: NSError?
                let status = converter.convert(to: output, error: &error) { _, state in
                    if supplied { state.pointee = .noDataNow; return nil }
                    supplied = true; state.pointee = .haveData; return buffer
                }
                guard status != .error, error == nil, let samples = output.int16ChannelData?[0], output.frameLength > 0 else { return }
                let meterNow = ProcessInfo.processInfo.systemUptime
                if meterNow - lastMeterTime >= 0.05 {
                    lastMeterTime = meterNow
                    var sum = 0.0
                    for i in 0..<Int(output.frameLength) { let value = Double(samples[i]) / 32768.0; sum += value * value }
                    let rms = sqrt(sum / Double(output.frameLength))
                    let level = max(0, min(1, (20 * log10(max(rms, 0.000001)) + 60) / 60))
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.lock.lock(); let current = self.transmitting && self.epoch == token; self.lock.unlock()
                        if current { self.onLevel?(level) }
                    }
                }
                let bytes = Data(bytes: samples, count: Int(output.frameLength) * 2)
                self.lock.lock()
                guard self.transmitting, self.epoch == token else { self.lock.unlock(); return }
                let frames = self.packets.append(bytes); self.lock.unlock()
                for frame in frames {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.lock.lock(); let current = self.transmitting && self.epoch == token; self.lock.unlock()
                        if current { self.onPCM?(frame) }
                    }
                }
            }
            tapInstalled = true
            engine.prepare(); try engine.start(); player.play()
        } catch { stop(); throw error }
    }
    func setTransmitting(_ enabled: Bool) {
        lock.lock(); epoch += 1; transmitting = enabled; packets.clear(); lock.unlock()
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
                self.queuedBuffers = max(0, self.queuedBuffers - 1)
            }
        }
    }
    func flushPlayback() {
        playbackEpoch += 1; queuedBuffers = 0; player?.stop()
        if running { player?.play() }
    }
    func stop(deactivate: Bool = true) {
        setTransmitting(false); playbackEpoch += 1; queuedBuffers = 0
        if let engine = engine { if tapInstalled { engine.inputNode.removeTap(onBus: 0) }; engine.stop() }
        tapInstalled = false
        player?.stop(); engine = nil; player = nil
        if deactivate { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
}
