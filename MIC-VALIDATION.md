# 3.5.6 (42) audio recovery

User reports no microphone callbacks and no speaker output despite received network data. Root cause on device remains unconfirmed.

Changes:
- Rebuild audio graph after AVAudioEngineConfigurationChange, asynchronously after notification return, rejecting obsolete engine notifications.
- Remove experimental muted capture mixer from 3.5.5; input tap captures directly.
- Watch input callbacks regardless of PTT. After three empty intervals or stalled playback queue, rebuild with default session mode and without voice processing.
- Compatibility mode has no voice-processing echo cancellation; test with headphones/separated devices.
- Stop PTT before recovery; require user to press again, no automatic transmission. Limit recovery to three attempts in thirty seconds.
- Display RUN/STOP, input/output routes, capture/PCM/playback callback counts while listening and speaking. Playback callbacks and UDP send completion do not guarantee audible output or server receipt.

Validation: Swift grammar, plist and ZIP integrity checked on Windows; no Xcode typecheck/build or physical iPhone verification available.

Device acceptance: build/install 3.5.6; use two devices in same room. Wait five seconds after joining; verify RUN and input callbacks. Speak each direction and verify PCM, sender TX, receiver RX and playback completions. Repeat with GPS enabled, speaker mute/unmute, wired/Bluetooth headset changes, phone interruption and background/foreground. Recovery must release PTT and must not loop endlessly. If still silent, capture diagnostics on both devices.
