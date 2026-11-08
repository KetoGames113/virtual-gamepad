

# 🎮 Virtual Gamepad

**Turn your phone into a real wireless Xbox controller for your PC — free, open source, no accounts, no ads.**

[![Latest Release](https://img.shields.io/github/v/release/kaifcoding/virtual-gamepad?label=latest%20release&color=6C5CE7)](https://github.com/kaifcoding/virtual-gamepad/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Made with Flutter](https://img.shields.io/badge/Made%20with-Flutter-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Made with .NET](https://img.shields.io/badge/Made%20with-.NET%208-512BD4?logo=dotnet&logoColor=white)](https://dotnet.microsoft.com)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/kaifcoding?label=sponsor&logo=githubsponsors&color=EA4AAA)](https://github.com/sponsors/kaifcoding)



> **Created by [kaifcoding](https://github.com/kaifcoding)** · © 2026 **Atomprod**. Free forever, MIT licensed — see [Credits & License](#-credits--license) below.

---

## What is this?

Virtual Gamepad is a two-part open source project:

| | |
|---|---|
| 📱 **Android app** (Flutter) | On-screen dual analog sticks, D-pad, ABXY face buttons, shoulder buttons, and analog triggers. Auto-discovers your PC over WiFi. |
| 🖥️ **Windows host app** (C#) | Creates a genuine virtual **Xbox 360 controller** via [ViGEmBus](https://github.com/ViGEm/ViGEmBus), so it works in *any* game or app that supports a normal controller — zero per-game setup. |

No subscriptions, no in-app purchases, no telemetry, no accounts. Just download and play.

## How it works

```
📱 Phone (Flutter app)  --UDP over WiFi-->  🖥️ PC (Windows host)  --ViGEmBus-->  🎮 Virtual Xbox 360 controller
```

The wire format is fully documented in [`PROTOCOL.md`](PROTOCOL.md) if you're curious how it works under the hood.

## ✨ Features

- Dual analog sticks with full-range 16-bit precision
- Analog L2/R2 triggers (pressure slider, not just on/off)
- Full D-pad, ABXY, shoulder buttons, Start/Back
- Auto-discovery of PCs on your WiFi network — tap and play
- Manual IP entry fallback for tricky networks
- Multiple phones can connect at once, each gets its own virtual controller
- Keeps your phone screen locked to the right orientation while playing

## ⬇️ Download

**[Go to the Releases page →](https://github.com/kaifcoding/virtual-gamepad/releases/latest)**

Every release has both apps attached, ready to run — no build tools, no SDKs, no cloning anything:

| File | What it is |
|---|---|
| `VirtualGamepad.apk` | The Android app. Copy to your phone and tap to install. |
| `VirtualGamepadHost-Setup.exe` | The Windows installer — Start Menu + Desktop icons, uninstaller included. |

### 📲 Install on your phone

Download `VirtualGamepad.apk` from the release page directly on your phone (or copy it over), then tap it to install. Android will ask permission to install from this source the first time — that's expected for any app outside the Play Store — allow it, then install.

### 🖥️ Set up your PC

1. Install **[ViGEmBus](https://github.com/ViGEm/ViGEmBus/releases/latest)** once — this is the driver that makes Windows see your phone as a real controller. Reboot if prompted.
2. Run `VirtualGamepadHost-Setup.exe` and follow the wizard (tick "Create a desktop icon" if you want one — it's on by default). No admin rights needed; it installs to your user profile.
3. **Windows SmartScreen will likely warn you** the first time — "Windows protected your PC." This is expected for any free/unsigned app (code-signing certificates cost money this project doesn't spend). Click **"More info" → "Run anyway."**
4. Launch **Virtual Gamepad Host** from the Start Menu or the desktop icon. The window shows your PC's IP address(es) — that's what you'll enter (or auto-discover) from the phone. Click "Show connection log" to see live connection activity.
5. Allow the app through **Windows Firewall** when prompted (check all network types — Domain, Private, *and* Public). If the prompt never appears, run [`windows-app/open-firewall-port.ps1`](windows-app/open-firewall-port.ps1) as Administrator to open the port manually.

### 🔗 Connect

1. Make sure your phone and PC are on the **same WiFi network**.
2. Open the app — it searches automatically and lists your PC by name.
3. Tap it to connect. If nothing shows up after a few seconds (see [Troubleshooting](#-troubleshooting)), type the IP shown in the PC's window instead.

## 🩺 Troubleshooting

**The Windows app seems to not open at all**
Almost always **Windows SmartScreen** silently blocking it (see step 3 above) — look for a blue "Windows protected your PC" dialog, possibly behind other windows, and click "More info → Run anyway." If you truly see nothing, try running it from a terminal (open PowerShell in the install folder and run `.\VirtualGamepadHost.exe`) so any startup error has a chance to print.

**"Failed to create virtual controller" on the PC**
Install ViGEmBus, then restart the host app.

**Auto-discovery doesn't find the PC**
This is the most common issue and it's almost always the *network*, not the apps:
- Confirm phone and PC are on the exact same WiFi network (not phone hotspot + PC on ethernet from a different router, not a guest network for one and main for the other).
- Many routers — especially mesh systems (eero, Google Nest WiFi), guest networks, and public/hotel WiFi — enable **"AP isolation" / "client isolation,"** which blocks device-to-device traffic on purpose for security. This is a router setting, not something the apps can bypass. Check your router's admin settings, or connect both devices to a different network without isolation.
- Confirm Windows Firewall allowed `VirtualGamepadHost.exe` on **all** profiles — rerun [`open-firewall-port.ps1`](windows-app/open-firewall-port.ps1) as Administrator to be sure.
- Watch the PC app's log (click "Show connection log") while the phone searches — if you never see `Discovery request from ...` lines appear, the broadcast traffic isn't reaching the PC at all.
- **Manual IP entry always works** even when auto-discovery can't — type the IP shown in the PC app into the phone app.

**"No response" after entering an IP manually**
- Double check the IP — it changes if you reconnect to WiFi or restart the PC.
- Confirm the Virtual Gamepad Host window is actually running.
- Port `47998/UDP` needs to be reachable — see the firewall steps above.

**Input feels laggy**
This runs over UDP on WiFi, so it depends on your router and network congestion. A 5GHz network with fewer connected devices helps a lot.

## 🗺️ Roadmap

- [x] WiFi transport (UDP), full Xbox 360 button/axis mapping
- [x] Auto-discovery of PCs on the local network
- [x] Multiple phones connecting simultaneously
- [x] Windows host with a proper branded GUI window (not just a console)
- [x] Windows installer with Start Menu + Desktop shortcuts and uninstaller
- [x] Custom app icon (Android + Windows), custom app ID (`in.atomprod.vgamepad`)
- [x] Portrait-locked menus, landscape-locked gamepad screen
- [x] One-click downloads via GitHub Releases
- [ ] Bluetooth transport (fallback when there's no shared WiFi network)
- [x] Customizable button layout / remapping in-app
- [x] Rumble/vibration feedback from PC back to phone
- [x] Windows tray icon (minimize-to-tray)
- [ ] iOS build (Flutter already supports it; needs a paid Apple developer account for signing)

## 🧑‍💻 Building from source (optional, for contributors)

You don't need any of this to just use the apps — see [Download](#-download) above. This is only for people who want to modify the code.

**Android app** — needs the [Flutter SDK](https://docs.flutter.dev/get-started/install):
```bash
cd android-app
flutter create --platforms=android --org in.atomprod .
cp manifest-overrides/AndroidManifest.xml android/app/src/main/AndroidManifest.xml
flutter pub get
dart run flutter_launcher_icons
flutter run              # with a device/emulator connected
```

**Windows app** — needs the [.NET 8 SDK](https://dotnet.microsoft.com/download):
```bash
cd windows-app
dotnet run
```

**Cutting a new release (maintainers):** push a version tag and the `Release` GitHub Actions workflow builds both apps and attaches them to a new GitHub Release automatically:
```bash
git tag v1.0.1
git push origin v1.0.1
```

## 🤝 Contributing

Issues and pull requests welcome. It's all MIT licensed — use it, fork it, remix it, sell it, whatever helps you.

## 💜 Support this project

If Virtual Gamepad saved you the cost of a real controller, consider sponsoring the maintainer on GitHub Sponsors:

<a href="https://github.com/sponsors/kaifcoding" target="_blank"><img src="https://img.shields.io/badge/Sponsor-on%20GitHub-EA4AAA?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="GitHub Sponsors"></a>

*(Points at `github.com/sponsors/kaifcoding` — this only works once that account is enrolled in GitHub Sponsors; set that up first if it isn't already.)* It's entirely optional and doesn't unlock anything — every feature stays free for everyone either way.

## 🙌 Credits

Created with ❤️ by [kaifcoding](https://github.com/kaifcoding) · © 2026 Atomprod. See [NOTICE](NOTICE) for attribution terms if you fork or redistribute this project.

## 📄 License

[MIT](LICENSE) — free for anyone to use, modify, and redistribute, including commercially.
## New in this build

- **Per-stick sensitivity & deadzone** — edit layout → tap a stick (sensitivity 20%–300%).
- **Tilt steering** — edit layout → (tap empty space) → *Tilt steering* tab. Phone held like a wheel in landscape; drives left/right stick X. Sensitivity, deadzone, smoothing, invert, *Set center*; a small calibrate button appears next to the edit button during play.
- **A / B / X / Y are separate controls** — move, resize, recolour or hide each one independently. Old layouts are migrated automatically.
- **Trigger lock** — tap LT/RT in the editor → *Double-tap to lock*. Double-tap = held fully pressed; touch again to release.
- **Aim & fire (LT/RT)** — touch = aim with the right stick, pull further = full press (fire). Adjustable *Fire pull*.
- **Per-stick response curve and Y gain**, **tilt curve**, **auto-center for tilt**, **trigger lock level**, and **toggle mode** for buttons (tap on / tap off).
- **Auto-switch profile by game (optional)** — the PC app reports the foreground game (new packet type 8); in the editor's General tab turn on *Auto-switch*, then tap *Use for "<game>"* while the game is in front. Requires the updated PC app.
- **Player name** — set it on the connect screen (or *Player name* in the editor's General tab, changeable while playing). The PC app lists every connected player by name; duplicate names get " (2)", " (3)"… Requires the updated PC app only for the unique-name/list display.
- **Turbo (rapid fire)** for any button (~12 presses/s while held) — editor → tap the button → *Turbo*.
- **Auto-sprint** — left stick pushed fully forward clicks L3 automatically (editor → tap the left stick).
- **Gyro aim** — editor → tap empty space → *Gyro aim* tab: rotate the phone to move the right stick (sensitivity, invert Y).

## UI overhaul

- **Gaming theme** — neon cyan/magenta on dark, chamfered HUD cards, Orbitron + Rajdhani fonts (Google Fonts; swap in your own via `assets/fonts/README.md`). Simplified connect screen (name + layout button on one row).
- **Fixed: hiding one control made all of them disappear.** The hidden control left a non-positioned child in the Stack, which collapsed it to 0×0. Hidden controls are now a zero-size `Positioned` and the Stack uses `StackFit.expand`.
- **New editor** (`lib/screens/layout_editor.dart`): slim dock (Done · profiles · undo · grid · hidden-controls tray · settings), an inspector for the selected control (size, opacity, colour, nudge arrows, hide/show, "More settings"), and a settings dialog (General / Tilt / Gyro / Games). Tap empty space to deselect.
- **Better moving**: magnet guides (centre of screen / other controls), grid snap, nudge arrows, undo (up to 40 steps), "Hidden controls" tray to bring hidden buttons back.

## Game rumble, tray icon and font

- **Game rumble (PC -> phone)** — when a game rumbles the virtual controller, your phone vibrates. Editor -> tap empty space -> *General* -> *Game rumble* (0 = off, up to 100%). Uses the phone's real vibration motor (with intensity on phones that support it). Needs the updated PC app.
- **Windows tray icon** — minimizing the PC app hides it to the system tray and the server keeps running; click the tray icon to reopen, right-click for *Exit*. The close button (X) still quits.
- **Bundled font** — *18 Khebrat Musamim Bold* is bundled in `android-app/assets/fonts/` and used for the whole app (works offline, supports Arabic and Latin). Make sure you have the right to redistribute the font.

## New look

- **Animated main screen** — drifting neon orbs, a gliding synthwave floor and floating particles behind neon-framed panels, a pulsing logo and a glowing CONNECT button.
- **New controls** — glossy A/B/X/Y spheres, capsule bumpers (LB/RB), a cross-shaped D-pad whose arms light up, sticks with a guide ring and a glowing knob, and triggers with a pressure gauge.
- **Re-tuned default layout** — triggers + bumpers in a top row, D-pad and left stick under the left thumb, right stick and A/B/X/Y under the right thumb, and the system buttons grouped in the middle. Existing saved layouts are kept; *Reset* in the editor applies the new defaults.


## Latency, auto-reconnect and turbo speed

- **Ping indicator** — a small badge at the top centre of the gamepad screen shows the round-trip time to the PC (green < 40 ms, amber < 90 ms, red above). Needs the updated PC app (new packet types 10/11, see `PROTOCOL.md`).
- **Auto-reconnect** — if the PC stops answering for ~3 s the badge shows *Reconnecting…*, the phone keeps re-introducing itself (and follows a Wi-Fi address change), and everything is released so nothing stays held. It returns to the menu after ~30 s. The PC now remembers each phone's name, so a phone that was dropped and comes back is no longer listed as "Unknown device".
- **Turbo speed** — editor → tap empty space → *General* → *Turbo speed* (4–20 presses per second). It applies to rapid-fire buttons and to the *Turbo* option of the Aim & fire triggers (editor → tap LT/RT → *Aim & fire* → *Turbo (rapid fire)*).
