# 3.5.7 (43): iPhone audio initialization audit

Native Swift AVFoundation: AVAudioSession, AVAudioEngine, AVAudioPlayerNode, AVAudioConverter. Build uses iphoneos SDK. PCM 16kHz mono Int16/640-byte frames is the intercom wire format, not Android hardware code.

Confirmed code defects corrected:
- Initial voice-processing startup errors previously bypassed the fallback. Now cleanly dispose/deactivate and attempt a new default-mode engine without voice processing, once. Both failure details survive if neither works.
- Generic no-microphone error previously conflated invalid capture format and converter creation failure. Permission, input hardware/tap format, output hardware format and conversion initialization now have distinct errors.
- Session preferences are requested while inactive and are nonfatal hints. The converter uses actual tap format. An empty input route can select an available built-in mic; existing headset routes are preserved.
- Startup error notice lasts 20 seconds.

Existing bounded runtime recovery, transport protocol and GPS preserved. Default-mode fallback does not provide voice-processing echo cancellation.

Validation on Windows: Swift grammar, plist parsing, build target and archive integrity. NOT Xcode typechecked, compiled or physically tested. Do not claim that audible audio is fixed until two real devices have passed bidirectional testing.

Physical acceptance: install 3.5.7, grant mic permission, join same room on two devices, test both directions with speaker on. Verify Thu > 0 while listening, PCM > 0 only when PTT granted, playback completions on receiver and audible speech. Repeat GPS on/off and headset/interruption recovery. Record full startup error if any; compare built-in mic with Bluetooth disconnected. No voice transmission may auto-resume during recovery.
