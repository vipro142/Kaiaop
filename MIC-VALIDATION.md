# 3.5.9 (45) — optional native echo cancellation and compact controls

User confirmed capture and playback work in Audio Queue 3.5.8. Preserve this backend.

Adds AVAudioSession.setPrefersEchoCancelledInput, guarded by iOS 18.2 availability and isEchoCancelledInputAvailable. Uses playAndRecord/default as required by Apple. EC preference is saved and defaults on; actual isEchoCancelledInputEnabled is displayed separately. Unsupported routes/devices or preference errors do not stop normal audio. This API is supported only on certain 2024-or-later iPhones, not all iPhones/iOS versions. It cancels built-in speaker echo, not all background noise or nearby devices. EC toggle rebuilds queues while PTT is off; it is disabled during PTT. No automatic transmit resume.

UI: remove volume slider; mic waveform, EC, speaker menu and route picker share one compact row. Technical diagnostics/traffic collapse under Chi tiết âm thanh; faults stay visible. GPS None label shortened.

Validation on Windows: Swift grammar and plist parsing, archive integrity. Xcode compile and actual EC/UI behavior on iPhone remain unverified. Existing audio queue and transport format unchanged.

Device checks: compare EC on/off with built-in speaker and mic on supported iPhone; confirm status reports actual state. Check unsupported iPhone/iOS and headset routes continue audio with truthful EC unavailable status. Test both speech directions, EC preference after relaunch, PTT toggle disabled, speaker mute and route selection, compact layout on portrait/landscape, GPS selector None and GPS transmission.

Reference: https://developer.apple.com/documentation/avfaudio/avaudiosession/setprefersechocancelledinput(_:)
