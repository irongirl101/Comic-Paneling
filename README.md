<img src="Sources/Resources/Panels.png" width="80" align="left" style="margin-right: 16px; border-radius: 14px;" />

# Panels

**A cross-platform comic book reader for macOS and Android with automatic panel detection.**

> **This app was fully vibe coded** — designed and built end-to-end through natural language conversation with an AI coding assistant, with almost zero manual code writing.

<br/>

---

## Download

### macOS
If you just want to run the macOS app without touching the source code, download the latest **Panels-macOS.zip** from the Releases page.

Unzip it, drag `Panels.app` into your `/Applications` folder, then open Terminal and run this before launching it:

```bash
xattr -rd com.apple.quarantine /Applications/Panels.app
```

After that, double-click the app to open it normally.

**Why is this needed?** Because the app is not signed with an Apple Developer certificate, macOS quarantines anything downloaded from the internet and will show a "damaged" error if you try to open it directly. The command above removes that quarantine flag. You only need to do it once.

**System requirement:** macOS 14 Sonoma or later, Apple Silicon (arm64).

### Android
For Android devices, build the APK from source using the instructions in the Getting Started section below, or download a pre-built APK from the Releases page (if available).

**System requirement:** Android 7.0 (API level 24) or later.

---

## What is Panels?

Panels is a dark-mode comic reader for macOS and Android that automatically figures out where the panels are on each page and lets you step through them one at a time. Drop in a `.cbz` or `.zip` archive and the app handles the rest — no configuration needed.

### Features

- **Library** — manage all your imported comics from one shelf across both platforms
- **Automatic Panel Detection** — two computer-vision algorithms (XY-Cut and Contour) written in Kotlin shareable between macOS and Android, analysing each page and identifying panel boundaries without any manual input
- **Guided Reading Mode** — step through panels one by one with a spotlight that dims the rest of the page so you stay focused
- **Focus Mode** — full-panel crop view that zooms precisely to the detected panel boundary
- **Controls & Gestures** — trackpad pinch and keyboard shortcuts on macOS; intuitive swipe, pan, and pinch-to-zoom gestures on Android
- **Reading Direction** — left-to-right for Western comics, right-to-left for manga
- **Reading Progress** — remembers where you left off in every book
- **Fullscreen** — edge-to-edge dark layout; the comic fills the whole display
- **Settings** — adjust spotlight intensity, default layout mode, and clear imported data

---

## Requirements

| Requirement | Version | Platform |
|---|---|---|
| macOS | 14 Sonoma or later | macOS |
| Android | 7.0 (API level 24) or later | Android |
| JDK | 17 or later | Build Toolchain |
| Swift toolchain | Swift 5.9 or later | macOS build |
| Architecture | Apple Silicon or Intel (macOS) / ARM64 or x86_64 (Android) | Both |

---

## Getting Started

### 1. Install Prerequisites

For macOS compilation, install the Swift command-line tools:

```bash
xcode-select --install
```

For Android compilation and Kotlin Multiplatform compilation, ensure you have Java Development Kit (JDK) 17 or later installed. Verify it using:

```bash
java -version
```

### 2. Clone the repository

```bash
git clone https://github.com/irongirl101/Comic-Paneling.git
cd Comic-Paneling
```

### 3. Build & Run macOS App

By default, the macOS app builds as a native Swift project. Run:

```bash
swift build
swift run Panels
```

The first build fetches the ZIPFoundation dependency, so you need an internet connection. When it finishes, the app window opens and the Panels icon appears in your Dock.

Note: To build the macOS app using the shared Kotlin Multiplatform library instead of the local Swift fallback implementation, compile the XCFramework first:

```bash
./gradlew :shared:assembleReleaseXCFramework
```

And then run `swift build` and `swift run Panels`.

### 4. Build & Run Android App

Open the repository root in Android Studio to let it import the project, then click Run.

Alternatively, from the terminal, build and install the debug app on an attached device or emulator:

```bash
./gradlew :androidApp:installDebug
```

---

## Importing a Comic

Panels reads CBZ files (Comic Book ZIP), the most common DRM-free comic format.

### On macOS:
1. Open the app
2. On the library screen, either click **Import Comic** in the top right, or drag a `.cbz` or `.zip` file from Finder straight onto the window
3. Fill in the title, author, and reading direction
4. Click **Complete Import** — the app extracts the archive, processes each page, and detects all the panels
5. Click the cover to start reading

### On Android:
1. Open the app
2. Tap the **Import** button on the library screen
3. Select a `.cbz` or `.zip` file from your device storage
4. Fill in the title, author, and reading direction in the dialog
5. Tap **Complete Import** — the KMP shared importer extracts the archive, processes each page, and detects the panels
6. Tap the cover to start reading

---

## Controls

### macOS (Guided & Focus Modes)

| Action | Control |
|---|---|
| Next panel | Right arrow key |
| Previous panel | Left arrow key |
| Zoom in | Cmd + or pinch out |
| Zoom out | Cmd - or pinch in |
| Reset zoom | Cmd 0 |
| Switch view mode | Picker in the top bar |
| Back to library | Library button or Esc |

### Android (Guided & Focus Modes)

| Action | Control |
|---|---|
| Next panel | Tap right side of the screen / Swipe left |
| Previous panel | Tap left side of the screen / Swipe right |
| Zoom / Pan | Pinch to zoom, drag to pan |
| Back to library | System back button / Back button in top bar |

---

## Building a Release Binary Yourself

### macOS
If you want to produce your own distributable macOS app, run the included script:

```bash
./build_app.sh
```

This will:
1. Compile an optimised release build with `swift build -c release`
2. Assemble a proper `Panels.app` bundle with the correct directory structure, `Info.plist`, app icon, and bundled resources
3. Zip everything into `Panels-macOS.zip`, ready to upload to a GitHub Release

### Android
To build a release APK, run the following Gradle command:

```bash
./gradlew :androidApp:assembleRelease
```

The resulting unsigned release APK will be generated at `androidApp/build/outputs/apk/release/androidApp-release-unsigned.apk`.

---

## How Panel Detection Works

When you import a comic, two algorithms run on each page. The core logic is implemented in a Kotlin Multiplatform shared library (`shared` module) to ensure identical behavior on both macOS and Android:

**XY-Cut** slices the page along the lightest horizontal and vertical lines — the gutters between panels. It is fast and works well on standard grid layouts.

**Contour Detection** uses a custom connected-component contour tracing algorithm to trace the outlines of closed shapes on the page. It handles non-rectangular and overlapping panels better than XY-Cut alone.

After detection, a refinement step called **PanelSnapper** scans inward from each detected boundary, finding the exact pixel where the gutter ends and the artwork begins. This tightens up the polygon corners and handles slanted borders and dark-background pages.

---

## Project Structure

```
Comic-Paneling/
├── Package.swift                  # Swift Package Manager manifest
├── build.gradle.kts               # Root Gradle build configuration
├── settings.gradle.kts            # Multi-project Gradle settings
├── build_app.sh                   # macOS packaging script
├── Sources/                       # macOS native Swift application source
│   ├── App.swift                  # App entry point and AppDelegate
│   ├── DetectorTest.swift         # CLI test harness
│   ├── Models/                    # Swift Models (with KMP bridges)
│   ├── Services/                  # Swift Services (with KMP bridges)
│   └── Views/                     # SwiftUI Views
├── shared/                        # Kotlin Multiplatform Shared Module
│   ├── build.gradle.kts           # KMP build configuration
│   └── src/
│       ├── commonMain/kotlin/     # Shared models, panel detector, snapper, and progress manager
│       └── commonTest/kotlin/     # Unit tests for shared logic
├── androidApp/                    # Android Application Module
│   ├── build.gradle.kts           # Android App build configuration
│   └── src/main/
│       ├── java/                  # Android Activities and Compose Views (MainActivity.kt)
│       └── res/                   # Android Resources
└── README.md
```

---

## Troubleshooting

### macOS Troubleshooting

**`swift: command not found`**  
Run `xcode-select --install` and try again once it finishes.

**Build fails with a dependency error**  
Make sure you are connected to the internet, then run `swift package resolve` before `swift build`.

**The window is very small or the content looks clipped**  
Drag the window edge to resize it. The minimum supported size is 500 x 850 points.

**Import fails for `.cbr` files**  
CBR is a RAR archive, which macOS cannot open natively. Convert the file to CBZ first using a tool like Calibre or ComicTagger.

### Android Troubleshooting

**`Unsupported class file major version` or Java errors during build**  
Ensure your `JAVA_HOME` environment variable is pointing to JDK 17 or higher.

**Build fails due to missing Android SDK or SDK build tools**  
Ensure your `local.properties` contains the correct path to your Android SDK (e.g. `sdk.dir=/Users/username/Library/Android/sdk`).

---

## License

MIT — see [LICENSE](LICENSE) for details.
