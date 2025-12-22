# muse v0.5

Capture your thoughts with a tap. Share them beautifully.

muse turns fleeting ideas into shareable moments or memories. Tap, speak, and your words appear — with aesthetic templates to share on X/stories/etc, save to your library, or send to friends & family.

> **Note:** This version uses our first ring prototype PCB with known BLE disconnect issues. v1.0 is in development with significant PCB improvements and mold design improvements.

---

## How It Works

1. **Tap and hold** the frosted area of ring until the **green LED** lights up
2. Speak your thought
3. Release — your muse appears in the feed after a few seconds
4. Long-press any card to **share** as a beautiful image

All transcription happens **on-device** using Whisperkit's small model.

---

## LED Indicators

| LED | Meaning |
|-----|---------|
| Green (solid) | Recording active |
| Blue (blinking) | Connecting/reconnecting — keeps trying until solid blue |
| Blue (solid) | Successfully connected |
| Red (on case) | Battery dead — charge for ~1.5 hours or overnight |

---

## Ring & Charging

**Charging the ring:**
- Place ring in case
- **Case must be connected to USB-C to charge** — the case LED may light up without USB, but it won't actually charge
- If LED on ring is **red** when placed in case, battery is dead — charge for ~1.5 hours or overnight
- Battery percentage can be inaccurate; charge when you see a red LED signal
- Battery curve problems may cause inaccurate readings of 100% or 0% at times.

**Connection tips:**
- Keep ring **within 5-10 feet** of your phone — no offline recordings in this version
- If connection drops, ring will flash blue several times and keep trying to reconnect
- Also use the electrical connection in the case for reconnects if you need to
- Often times the ring may not connect, but it's not actually out of battery. It just had it's reconnect cycle timeout most likely, and needs to be sent a wakeup signal (which can be done with the charging case).
- BLE disconnects are a known issue in this PCB version, and I apologize for how it might affect this initial experience!! 

---

## Gesture Modes

The ring supports two modes — **voice** and **music control**. Use one at a time.

**Voice mode (default):**
- Tap and hold frosted area → green LED → speak → release
- Your transcribed muse appears in the feed

**Music control mode:**
- Swipe up on the capacitive touch/frosted area → skip to next song
- More gestures (volume, play/pause) coming in future updates
- Tends to have fewer disconnects than voice mode
- Right now, it's kind of an art to get this shit right lol. I will demo with you in person, but the accuracy of this gesture isn't optimal yet. And it's more of something for you to just test and let me know what other gestures you would want (we have horizontal in updated PCB f.e.).

**Troubleshooting:**
- If voice or music control features aren't working, try toggling between music and voice mode. And when you can't switch modes, it means the device needs a connection refresh. In which case putting it on the charging case and trying to refresh/reconnect will often fix it.
- Future update will make mode switching automatic.

**Audio & Transcription Accuracy:**
- In this current muse demo app, audio cleanup is very minimal. And doesn't use any AI cleanup or voice isolation. To keep things simple and offline.
- So transcription works well in quiet environments, but with background noise and music it becomes much less accurate.
- In non-SDK versions of Muse, it will come with voice isolation and voice recognition flow so your voice is recognized.

---

## Development Setup

**Requirements:**
- Xcode 15.0+
- iOS 17.0+ device (simulator won't work for BLE)
- Apple Developer account (for device deployment)

**Steps:**

1. Clone the repo
   ```bash
   git clone <repo-url>
   cd muse
   ```

2. Open in Xcode
   ```bash
   open muse.xcodeproj
   ```

3. Wait for Swift packages to resolve
   - **WhisperKit** (remote) — downloads automatically from GitHub
   - **MuseSDK** (local) — included in repo, links automatically

4. Select your device as the build target (not simulator)

5. Build and run (`Cmd + R`)

**First launch:**
- WhisperKit downloads the transcription model (~40MB) on first use
- Grant Bluetooth permission when prompted
- Location permission is optional (for shareable cards)

---

## Build Your Own

The core of muse is simple: **ring audio capture + on-device transcription**.

Use this as a foundation for your own workflows — journaling apps, agents, fun companions, idea capture systems, an LLM that controls your life via your muse ring as input, or anything else you dream up.

**Want access to more gestures?**

The ring hardware supports additional touch gestures and IMU-based air gestures that aren't exposed in this version. If you'd like to build on top of these capabilities, text Naveed something you've already built with muse and he'll share access.

---

## Feedback

Working on v1.0 in Shenzhen with major updates to PCB, mold design, charging case, and more.

**Text Naveed: 650-388-2362**

Share your thoughts on design, interactions, feature requests, bugs — all of it helps. The more critical the feedback, the better. 

I will most likely request to have a phone call with you to discuss your feedback after a few days, and early access to v1.0.

And text me if you'd like to share something you've built with muse!