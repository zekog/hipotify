# 🎶 Hipotify

Hipotify is a free, open-source, and ad-free music player for Android based on Tidal with Hi-Res sound. It has a clean interface similar to Spotify, built with Flutter for a premium native experience.

## Features
- ❌ **Ad-Free Listening**: Stream directly from Tidal without interruptions.
- 💿 **Lossless Audio**: Support for FLAC and Hi-Res sound quality.
- 🎧 **Huge Catalogue**: Powered by the full TIDAL library and HiFi APIs.
- ☁️ **Cloud Sync & Social**: Sync likes and playlists across devices and discover community playlists via **Playlist Net**.
- 🔎 **Advanced Search**: Intelligent scoring algorithm to find the most accurate tracks and artists.
- 🎨 **Artist Profiles**: Organized discographies with clear separation between Albums and Singles & EPs.
- 🎭 **Dynamic Themes**: Premium glassmorphism aesthetic with Material You (Android 12+), Catppuccin palettes, and AMOLED black mode.
- 🎵 **Synced Lyrics**: Premium lyrics experience with tap-to-seek functionality.
- 💾 **Smart Downloads**: Export songs as lossless .flac files with full metadata (Android/Linux).
- 📡 **Chromecast**: Stream to your TV with synchronized lyrics (Android only).
- 📊 **Stats for Nerds**: Real-time technical details (bit depth, sample rate, etc.).
- 🐧 **Linux Support**: Support for Linux with AppImage builds.

## ⚙️ How It Works
Hipotify acts as a mobile frontend that fetches lossless audio directly from TIDAL.

1. You search for a song.
2. Hipotify sends the query to a HiFi API.
3. The API returns a direct TIDAL lossless stream link.
4. Hipotify plays the audio using a high-performance playback engine.

## 🔗 Credits & Related Projects
- [hifi](https://github.com/sachinsenal0x64/hifi) - Tidal Music integration for Subsonic/Jellyfin/Plexamp
- [tidal-ui](https://github.com/uimaxbai/tidal-ui) - Original Inspiration for the synced lyrics and UI logic
- [hifi-api](https://github.com/uimaxbai/hifi-api) - API that fetches the streams
- [spofree](https://github.com/redretep/spofree) - Inspiration for the feature set and design goals
- [Catppuccin](https://github.com/catppuccin/catppuccin) - Soothing pastel themes

## 🔎 API List
The following public HiFi API instances can be used in the app settings:

| Provider | Instance URL |
|----------|--------------|
| squid.wtf | `https://triton.squid.wtf` |
| squid.wtf | `https://aether.squid.wtf` |
| squid.wtf | `https://zeus.squid.wtf` |
| squid.wtf | `https://kraken.squid.wtf` |
| lucida | `https://wolf.qqdl.site` |
| lucida | `https://maus.qqdl.site` |

## 🚀 Setup
1. Clone the repository.
2. Run `flutter pub get` to install dependencies.
3. Configure your API base URL in the app settings.

## 🤖 Build Instructions

### Android
1. Install [Flutter SDK](https://docs.flutter.dev/get-started/install).
2. Setup [Android SDK](https://developer.android.com/studio).
3. Build options:
   - **APK**: `flutter build apk --release`
   - **Split APKs**: `flutter build apk --split-per-abi`
   - **App Bundle**: `flutter build appbundle`
4. Output: `build/app/outputs/flutter-apk/`

### iOS
> [!IMPORTANT]
> iOS builds require **macOS** with **Xcode** installed.

1. Run `flutter pub get`.
2. Run `cd ios && pod install && cd ..`.
3. Build: `flutter build ios --release`.
4. Output: `build/ios/iphoneos/Runner.app` (or `.ipa`).

---

<sub>**Disclaimer**: This project does not promote piracy. The use of third-party APIs is at the user's own responsibility. It is highly recommended to host your own instance of [hifi-api](https://github.com/uimaxbai/hifi-api) for personal use.</sub>
