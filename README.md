<img src="Sources/Resources/Panels.png" width="80" align="left" style="margin-right: 16px; border-radius: 14px;" />

# Panels

**A native macOS comic book reader with automatic panel detection.**

> **This app was fully vibe coded** — designed and built end-to-end through natural language conversation with an AI coding assistant, with almost zero manual code writing.

<br/>

---

## Download

If you just want to run the app without touching the source code, download the latest **Panels-macOS.zip** from the [Releases page](https://github.com/irongirl101/Comic-Paneling/releases).

Unzip it, drag `Panels.app` into your `/Applications` folder, and open it.

> **First launch note:** Because the app is not signed with an Apple Developer certificate, macOS will block it with a security warning the first time. To get past this, right-click (or Control-click) the app in Finder and choose **Open**, then click **Open** again in the dialog. You only need to do this once.
>
> Alternatively, from Terminal:
> ```bash
> xattr -cr /Applications/Panels.app
> ```
> Then open it normally.

**System requirement:** macOS 14 Sonoma or later, Apple Silicon (arm64).

---

## What is Panels?

Panels is a dark-mode comic reader for macOS that automatically figures out where the panels are on each page and lets you step through them one at a time. Drop in a `.cbz` or `.zip` archive and the app handles the rest — no configuration needed.

### Features

- **Library** — manage all your imported comics from one shelf
- **Automatic Panel Detection** — two computer-vision algorithms (XY-Cut and Contour) analyse each page and identify panel boundaries without any manual input
- **Guided Reading Mode** — step through panels one by one with a spotlight that dims the rest of the page so you stay focused
- **Focus Mode** — full-panel crop view that zooms precisely to the detected panel boundary
- **Zoom** — pinch to zoom on trackpad, keyboard shortcuts, and zoom level stays put when you move between panels or pages
- **Reading Direction** — left-to-right for Western comics, right-to-left for manga
- **Reading Progress** — remembers where you left off in every book
- **Fullscreen** — edge-to-edge dark layout; the comic fills the whole display
- **Settings** — adjust spotlight intensity, default layout mode, and clear imported data

---

## Requirements

| Requirement | Version |
|---|---|
| macOS | 14 Sonoma or later |
| Swift toolchain | Swift 5.9 or later |
| Architecture | Apple Silicon or Intel |

You do not need the full Xcode IDE. The Swift command-line tools are enough.

---

## Getting Started

### 1. Install Swift

If you have never installed Swift, open Terminal and run:

```bash
xcode-select --install
```

Follow the prompts. Once it finishes, check that it worked:

```bash
swift --version
```

You should see Swift 5.9 or higher.

### 2. Clone the repository

```bash
git clone https://github.com/irongirl101/Comic-Paneling.git
cd Comic-Paneling
```

### 3. Build

```bash
swift build
```

The first build fetches one dependency ([ZIPFoundation](https://github.com/weichsel/ZIPFoundation)) so you need an internet connection. It takes a minute or two. When it finishes you will see:

```
Build complete!
```

### 4. Run

```bash
swift run Panels
```

The app window opens and the Panels icon appears in your Dock.

---

## Importing a Comic

Panels reads CBZ files (Comic Book ZIP), the most common DRM-free comic format.

1. Open the app
2. On the library screen, either click **Import Comic** in the top right, or drag a `.cbz` or `.zip` file from Finder straight onto the window
3. Fill in the title, author, and reading direction
4. Click **Complete Import** — the app extracts the archive, processes each page, and detects all the panels
5. Click the cover to start reading

---

## Controls

### Guided Mode

| Action | Control |
|---|---|
| Next panel | Right arrow key |
| Previous panel | Left arrow key |
| Zoom in | Cmd + or pinch out |
| Zoom out | Cmd - or pinch in |
| Reset zoom | Cmd 0 |
| Switch view mode | Picker in the top bar |
| Back to library | Library button or Esc |

### Focus Mode

| Action | Control |
|---|---|
| Next panel | Right arrow key |
| Previous panel | Left arrow key |
| Zoom in / out | Cmd + / Cmd - or trackpad pinch |

---

## Building a Release Binary Yourself

If you want to produce your own distributable (for example, to share with others or upload to a fork's releases page), run the included script:

```bash
git clone https://github.com/irongirl101/Comic-Paneling.git
cd Comic-Paneling
./build_app.sh
```

This will:

1. Compile an optimised release build with `swift build -c release`
2. Assemble a proper `Panels.app` bundle with the correct directory structure, `Info.plist`, app icon, and bundled resources
3. Zip everything into `Panels-macOS.zip`, ready to upload to a GitHub Release

The script prints the target architecture and macOS version at the end so you know exactly what the binary was built for.

---

## How Panel Detection Works

When you import a comic, two algorithms run on each page:

**XY-Cut** slices the page along the lightest horizontal and vertical lines — the gutters between panels. It is fast and works well on standard grid layouts.

**Contour Detection** uses Apple's Vision framework to trace the outlines of closed shapes on the page. It handles non-rectangular and overlapping panels better than XY-Cut alone.

After detection, a refinement step called **PanelSnapper** scans inward from each detected boundary, finding the exact pixel where the gutter ends and the artwork begins. This tightens up the polygon corners and handles slanted borders and dark-background pages.

---

## Project Structure

```
Comic-Paneling/
├── Package.swift                  # Swift Package Manager manifest
├── Sources/
│   ├── App.swift                  # App entry point and AppDelegate
│   ├── DetectorTest.swift         # CLI test harness (swift run Panels --test)
│   ├── Models/
│   │   ├── ComicBook.swift        # ComicBook, ComicPage, ComicPanel models
│   │   └── ReadingProgress.swift  # Reading progress saved to UserDefaults
│   ├── Services/
│   │   ├── ComicImporter.swift    # CBZ/ZIP extraction and cataloguing
│   │   ├── PanelDetector.swift    # XY-Cut and Contour detection algorithms
│   │   ├── PanelSnapper.swift     # Sub-pixel polygon edge refinement
│   │   └── SampleComicBuilder.swift
│   ├── Views/
│   │   ├── MainSplitView.swift    # Root navigation split view
│   │   ├── LibraryGridView.swift  # Comic bookshelf and import UI
│   │   ├── DesktopReaderView.swift# Reader chrome and toolbar
│   │   ├── DesktopGuidedView.swift# Guided spotlight reading mode
│   │   ├── DesktopFocusView.swift # Focus (cropped) reading mode
│   │   ├── DesktopPanelEditor.swift
│   │   └── Components/
│   │       ├── ComicCard.swift    # Library grid thumbnail card
│   │       ├── GlassyButton.swift # Shared button style
│   │       └── PageMiniMap.swift  # Page overview thumbnail strip
│   └── Resources/
│       ├── Panels.png             # App icon
│       └── SampleComics/
└── README.md
```

---

## Troubleshooting

**`swift: command not found`**  
Run `xcode-select --install` and try again once it finishes.

**Build fails with a dependency error**  
Make sure you are connected to the internet, then run `swift package resolve` before `swift build`.

**The window is very small or the content looks clipped**  
Drag the window edge to resize it. The minimum supported size is 500 x 850 points.

**Import fails for `.cbr` files**  
CBR is a RAR archive, which macOS cannot open natively. Convert the file to CBZ first using a tool like [Calibre](https://calibre-ebook.com/) or [ComicTagger](https://github.com/comictagger/comictagger).

---

## License

MIT — see [LICENSE](LICENSE) for details.
