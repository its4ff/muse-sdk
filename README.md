# muse v0.5 
> technically less of an SDK, and more just a pure example app built for muse.

Capture your thoughts with a tap. 

This is an example Muse app, which you can use the existing code of to build nearly any workflow you'd like.
> **Note:** This version uses our first ring prototype PCB with known BLE disconnect issues. v1.0 is in development with significant PCB improvements and mold design improvements.

---

## How It Works

1. **Tap and hold** the frosted area of ring until the **green LED** lights up
2. Speak your muse - it can be anything. a thought, note, idea, to-do, command, quote, yap, memory...
3. Release — your muse appears in the feed after a few seconds
4. Long-press any card to **share** as an aesthetic image. View your memories on the muse map.

**The core workflow is as follows:**
Capacitive touch is pressed on the ring -> Green LED turns on, audio starts recording -> release, audio stops. audio packets are sent to your phone via bluetooth -> audio is saved on your phone + the transcription happens on your phone with whisperkit's smallest model. 

All data + workflows happen on device currently and are saved in Swift Data.
You can send the audio to the cloud for cleanup, storage on an external database, external workflows on the cloud, etc, etc. 

---

## Current Issues for v0.5

1. **Random disconnections over bluetooth (blue light flashes when disconnects happen. when you press and hold & green indicator doesn't come on, you're disconnected. troubleshooting issues farther below)**
2. Limited connection range: 5-10 ft from your phone
3. When washing hands or showering with the ring, it sometimes starts recording audio when water pressure hits the touch area (current version is 5atm waterproof).
4. Gestures for music aren't super smooth (don't always register, and you have to get used to the pressure and only swiping bottom to top or top to bottom on the textured touch area)
5. Audio quality (can be easily improved with cloud cleanup on ADPCM audio or wav file. just not implemented here to keep things all on device and simple).

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
- Also use the electrical connection in the case for reconnects if you need to. 
- Worst case you'll need to 'forget the device' in bluetooth settings and then reconnect
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

---

**Troubleshooting:**
- If voice or music control features aren't working, try toggling between music and voice mode. And when you can't switch modes, it means the device needs a connection refresh. In which case putting it on the charging case and trying to refresh/reconnect will often fix it.
- Future update will make mode switching automatic.

---

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

Use this as a foundation for your own workflows — journaling apps, agents, fun companions like a tamagotchi, idea capture systems, an LLM that controls your life via your muse ring as input, or anything else you dream up.

We're building several core apps & workflows on muse that will come with the version 1 release. If you need any ideas, ask Naveed. We have a 'request for builders' document of about 15 different unique apps that are perfect for muse.

**Want access to more gestures?**

The ring hardware supports additional touch gestures, haptic vibrations, and IMU-based air gestures that aren't exposed in this version. If you'd like to build on top of these capabilities, text Naveed something you've already built with muse and he'll share access.

---

## Feedback

Working on v1.0 in Shenzhen with major updates to PCB, mold design, charging case, and more.

**Text Naveed: 650-388-2362**

Share your thoughts on design, interactions, feature requests, bugs — all of it helps. The more critical the feedback, the better. 

I will most likely request to have a phone call with you to discuss your feedback after a few days, and early access to v1.0.

And text me if you'd like to share something you've built with muse!