# Build and install

## Requirements

- macOS with **Xcode 27** and [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- iPhones on **iOS 26 or later**, connected by cable or on the same Wi-Fi as the Mac
- An Apple ID signed in to Xcode (**Xcode > Settings > Accounts**). A free personal team works

The Xcode project is generated from `project.yml` and is not committed. `install-iphone.sh` runs `xcodegen generate` for you.
There are no API keys and no secrets: the app is fully offline apart from the local-network multiplayer.

## 1. Signing

```bash
cp Config/Signing.example.xcconfig Config/Signing.xcconfig
```

| Key | What |
|---|---|
| `KH_BUNDLE_ID` | A bundle identifier unique to you, for example `com.yourname.khel` |
| `DEVELOPMENT_TEAM` | Your Apple Developer Team ID (10 characters) |

`Config/Signing.xcconfig` is git-ignored.

## 2. Prepare each iPhone (once)

1. Turn on **Settings > Privacy & Security > Developer Mode** and restart the phone when asked.
2. Connect the phone with a cable, unlock it and tap **Trust**.
3. Enable **Connect via network** for the device in Xcode > Window > Devices and Simulators to install over Wi-Fi later.
4. After the first install: **Settings > General > VPN & Device Management**, trust your developer certificate.

## 3. Install

```bash
./install-iphone.sh                       # every paired iPhone (yours and your partner's)
./install-iphone.sh <device-id> ...       # only these
./install-iphone.sh --no-launch ...       # do not open the app afterwards
```

Find device ids with `scripts/list-iphones.sh`.

## 4. Keep it installed automatically

A free Apple team signs apps for 7 days. Turn on the hourly background job once and every paired iPhone is refreshed
before it expires: see [auto-install.md](auto-install.md).

## Free account limits

- A free team can have **3 apps** installed per device. Khel is one of them (alongside CineFlix this leaves one free slot).
- Apple limits how many new app ids a free team can register per week; reinstalling the same app does not count.
- A paid Apple Developer account removes the 7-day expiry.

## Simulator

```bash
xcodegen generate
xcodebuild build -project Khel.xcodeproj -scheme Khel -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```
