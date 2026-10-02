# 3.5.5 (41) — microphone capture investigation

Changes: explicit muted capture branch in AVAudioEngine; idempotent transmission state; per-second input-buffer and PCM-packet diagnostics; UDP completion error reporting and successful local-send byte accounting. Existing GPS behavior preserved.

The capture graph change is a candidate fix, not a confirmed root cause: Apple documents that an input tap alone can capture audio. No physical iPhone is attached here.

Validation here: Swift grammar parse and plist parsing only. Xcode compile and physical-device audio remain required.

Build with Codemagic. Install the new IPA on an iPhone; join the same room as a second device with speaker enabled. Hold PTT and speak for at least 5 seconds. Verify sound on the other device, then reverse direction. Check built-in microphone and a headset, GPS on/off, interruption recovery, and speaker mute. No local microphone sound should echo through the capture branch.

During PTT, Thu counts input callbacks/sec, PCM counts generated 20ms audio packets/sec (normally around 50). These counters measure callbacks, not audible speech. A moving waveform indicates nonzero input. The transmit byte counter indicates local UDP send completion, not server receipt. If silent, capture screenshots from sender and receiver, including waveform, Thu/PCM and send/receive counters.
