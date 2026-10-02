# 3.5.8 (44) — Native iOS Audio Queue backend

The user reports repeated zero capture callbacks, silent playback, and exhausted engine recovery on iPhone 17 Pro Max / reported iOS 27. The physical-device root cause of the prior AVAudioEngine path remains unconfirmed.

This version replaces that path with AudioToolbox input/output queues and AVAudioSession playAndRecord/default. It does not contain Android audio APIs. The deployment target remains iOS 15.0. Device-family compatibility is an implementation target, not a claim of testing all iPhones.

Implementation:
- Independent input and output queues, each with three 640-byte PCM buffers: 16kHz mono signed packed little-endian Int16, 20ms/frame.
- Output queues remain primed with silence between received packets. At most six additional received frames are pending; oldest dropped to bound latency.
- Input buffers are always recycled, including while PTT is off. Only granted PTT sends frames; generation checks discard stale callbacks after mute/stop/restart.
- Main-thread lifecycle, guarded callback data, queue identities checked, locks released before synchronous queue disposal. No disposal from callback threads.
- Existing OS interruption/route-change handling remains. Watchdog no longer automatically tears down and reopens audio repeatedly. Actual step/status stays on screen, with a manual retry action.
- UI shows v3.5.8 / Audio Queue plus input/output names, capture callbacks, generated PCM, output callbacks (including silence), and recycled buffers that contained received audio. None of these alone proves audible speech.
- Default mode has no voice-processing echo cancellation. Use headphones or separate devices when testing. Do not label this path as echo-cancelled.
- Existing GPS and transport source are unchanged.

Validation performed here on Windows: Swift grammar parsing, plist parsing, Xcode target/source inspection, archive integrity and GPS/transport byte comparison with the 3.5.7 source archive. These checks do not typecheck Apple SDK calls or run Core Audio. No Xcode build or physical-device audio test has run here.

Required acceptance on Codemagic/iPhone:
1. Build and install; confirm v3.5.8 / Audio Queue appears, rather than an older binary.
2. With built-in mic/speaker and microphone permission, join room and wait 5s. Both capture and speaker callbacks should advance even while PTT is off; PCM should not be sent while off.
3. Two devices in same room: speak for 5s each way; verify audible speech, waveform, generated PCM, sender TX and receiver RX. Then GPS on/off; confirm tracking remains functional.
4. Verify mute speaker, volume, wired/Bluetooth routes, device removal, interruption and foreground/background transitions. Recovery must never resume transmission without a new user action.
5. Rapid PTT/leave/rejoin: no stale voice transmission, crash or unlimited buffering. On failure, full error step and OSStatus must remain visible without restart loops. Use manual retry.
6. Test multiple iPhone/iOS versions before claiming broad compatibility.

References:
https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/AudioQueueProgrammingGuide/AQRecord/RecordingAudio.html
https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/AudioQueueProgrammingGuide/AQPlayback/PlayingAudio.html
