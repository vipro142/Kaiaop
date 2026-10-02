# LIVEPRO iOS GPS 3.5.0 (36) — source candidate

NOT BUILT WITH XCODE. NOT VERIFIED ON IPHONE. This is source, not an IPA.

GPS selector is in the setup screen, enabled only for Camera. Choices and IDs match the existing eight trackers. Selection persists. GPS uses high accuracy, no distance filter, background location mode and a visible iOS location indicator. Allow precise location; use the background permission button for Always access.

The app sends the latest fresh location at most once per second to the existing Traccar OsmAnd endpoint kailive1.ddns.net:5055. It does not invent fixes or repeatedly relabel old coordinates as new. iOS determines fix frequency. One request runs at a time; timeout is eight seconds; latest location is retried after network errors. This version does NOT maintain an offline history queue. Force-quitting the app can stop tracking.

Voice change: reset AVAudioConverter on the audio callback when a new transmit epoch begins, preventing resampler history crossing PTT sessions. Existing voice-processing audio, headset route recovery and interruption handling are retained. This is not a confirmed fix for the user's microphone fault; the exact symptom still needs reproduction on iPhone. GPS never changes AVAudioSession.

Build on a Mac: open LivePro.xcodeproj, choose the LivePro scheme and run on iPhone. Or run `bash build-unsigned.command` to create an unsigned IPA. Signing/provisioning is required for installation.

Required device checks:
- Mic permission, ten consecutive PTT presses, first syllable, speaker/headset/Bluetooth.
- Incoming phone call and headset reconnect; no stuck transmitting.
- Camera GPS selection, all eight IDs, restart retains choice, role change stops GPS.
- Precise/approximate/denied location, screen locked ten minutes.
- Traccar device timestamps while moving; connectivity loss/recovery; no duplicate stale fixes.

Validation performed on Windows: Swift grammar parsing and plist configuration only. No Apple SDK type-check, Xcode compile, XCTest or physical-device validation.
