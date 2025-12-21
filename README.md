# muse v0.5

Capture your thoughts with a tap. Share them beautifully.

muse turns fleeting ideas into shareable moments or memories. Tap, speak, and your words appear transcribed on your feed — ready to share to X, save to your library, or send to friends.

> **Note:** This version uses our first ring prototype PCB with known BLE disconnect issues. v1.0 is in development with hardware improvements and design improvements.

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
| Blue (blinking) | Connecting/pairing |
| Red | Low battery |

---

## Ring & Charging

**Charging the ring:**
- Place ring in case
- **Case must be connected to USB-C to charge** — the case LED may light up without USB, but it won't actually charge
- Battery percentage can be inaccurate; charge when behavior seems sluggish or when the green LED is not lit when you try to speak.

**Connection tips:**
- Keep ring **within 5-10 feet** of your phone — no offline recordings in this version
- If connection drops, try reconnects via the app
- Also use the electrical connection in the case for reconnects if you need to.
- BLE disconnects are a known issue in this PCB version

---

## Build Your Own

The core of muse is simple: **ring audio capture + on-device transcription**.

Use this as a foundation for your own workflows — journaling apps, agents, fun companions, idea capture systems, an LLM that controls your life via your muse ring as input, or anything else you dream up.

---

## Feedback

Working on v1.0 in Shenzhen with major updates to PCB, mold design, charging case, and more.

**Text Naveed: 650-388-2362**

Share your thoughts on design, interactions, feature requests, bugs — all of it helps. The more critical the feedback, the better. 

And share something you've built with muse!
