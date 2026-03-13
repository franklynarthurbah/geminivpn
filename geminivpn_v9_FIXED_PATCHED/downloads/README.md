# GeminiVPN — App Download Files

Place your compiled app installers in this directory.  
They will be served by nginx at `https://yourdomain/downloads/` and
tracked by the backend at `/api/v1/downloads/<platform>`.

## Expected Files

| Filename                  | Platform | Built from |
|---------------------------|----------|------------|
| `GeminiVPN.apk`           | Android  | `../android/` — `./gradlew assembleRelease` |
| `GeminiVPN-Setup.exe`     | Windows  | `../desktop/` — `npm run build:win` |
| `GeminiVPN.dmg`           | macOS    | `../desktop/` — `npm run build:mac` |
| `GeminiVPN.AppImage`      | Linux    | `../desktop/` — `npm run build:linux` |
| `GeminiVPN.deb`           | Linux    | `../desktop/` — `npm run build:linux` |
| `router-guide.pdf`        | Router   | Create manually |

## Quick Build Reference

```bash
# Android APK
cd ../android && ./gradlew assembleRelease
cp android/app/build/outputs/apk/release/app-release.apk downloads/GeminiVPN.apk

# Desktop (run on each OS)
cd ../desktop
npm install
npm run build:win    # → dist/GeminiVPN Setup 1.0.0.exe
npm run build:mac    # → dist/GeminiVPN-1.0.0.dmg  (macOS only)
npm run build:linux  # → dist/GeminiVPN-1.0.0.AppImage

# Copy to downloads folder
cp ../desktop/dist/*.exe downloads/GeminiVPN-Setup.exe
cp ../desktop/dist/*.dmg downloads/GeminiVPN.dmg
cp ../desktop/dist/*.AppImage downloads/GeminiVPN.AppImage
```

## iOS
iOS is distributed exclusively via the App Store / TestFlight.  
The download button redirects to: `https://apps.apple.com/app/geminivpn`
