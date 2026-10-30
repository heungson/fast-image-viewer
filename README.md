# Fast Image Viewer

A small native macOS app for opening images from a pasted file path or a direct image URL. Built with Swift and AppKit; no Electron, web server, or third-party dependencies.

## Use it

Open **Fast Image Viewer.app** in `~/Applications` once. Then:

1. Copy an image file path or direct image URL.
2. Press **Control–Option–I** from any app. The viewer opens the image address on your clipboard immediately.

You can also paste into the address field and press **Return**, drop an image onto the preview, or choose **Browse files…**. A copied Finder image file works with the clipboard shortcut too.

Accepted addresses include:

```text
/var/folders/xd/example/T/screenshot.png
/Users/you/Pictures/image with spaces.png
~/Pictures/photo.jpg
file:///Users/you/Pictures/image%20with%20spaces.png
https://example.com/image.png
```

Quoted paths and terminal-escaped spaces work. Web addresses must point directly to image data, rather than a webpage containing an image. Temporary screenshot files must still exist.

| Shortcut | Action |
| --- | --- |
| Control–Option–I | Open the image address on the clipboard, from anywhere |
| Command–Shift–V | Open from clipboard while the viewer is active |
| Command–L | Focus and select the address |
| Return | Open the entered address |
| Command–O | Browse for an image |
| Command–0 | Fit the image in the window |
| Command–1 | Show actual pixels |
| Command–plus / minus | Zoom in / out |
| Escape | Cancel a download, or hide the window |
| Command–W | Close the window and keep the shortcut active |
| Command–Q | Quit the app and release the shortcut |

Change or disable the global shortcut in **Fast Image Viewer → Global Shortcut**. Two alternate shortcuts are provided if another app uses the default. The menu bar photo icon also opens the viewer or clipboard image.

Closing the window keeps the app running for its global shortcut. After quitting or restarting your Mac, open the app again to enable the shortcut. This app does not change your login items or default image viewer.

Fit mode preserves the aspect ratio and avoids enlarging small images. At **100%**, each image pixel uses one physical screen pixel, including on Retina screens. Large images can be scrolled; transparency appears over a checkerboard. Animated GIFs use the native image view.

## Build and install

Requires macOS 13 or later and Xcode Command Line Tools with Swift. Builds for the current Mac’s architecture.

```sh
./scripts/build.sh
./scripts/install.sh
```

The build is in `build/Fast Image Viewer.app`; installation copies it to `~/Applications/Fast Image Viewer.app`. Open the installed app from Finder or Spotlight. Builds are signed locally with an ad-hoc signature, and are not notarized for distribution to other Macs.

To open an image from the terminal:

```sh
open -a "$HOME/Applications/Fast Image Viewer.app" "/absolute/path/to/image.png"
```

## Verification

```sh
./scripts/test.sh
```

Tests cover source parsing, paths with spaces, quotes and home expansion, file URLs, query preservation, decoding and metadata, missing files, folders, invalid data, HTTP downloads and errors, download size limits, and cancellation. The HTTP fixtures run only on loopback using Python 3’s standard library.

The live app was also checked with local paths, encoded file URLs, a public HTTPS WebP image, zooming, and missing-file feedback.

## Data handling and limits

Local images stay on your Mac. Web images are fetched only when you open an address, using an ephemeral network session without a persistent download cache. The app does not save image history, paths, clipboard contents, or telemetry. It stores the selected shortcut and window frame in macOS preferences.

Images use the formats supported by macOS ImageIO, including PNG, JPEG, HEIC, TIFF, GIF, BMP, and WebP on supported systems. The size limits are 80 MB and 120 megapixels. Network requests have a 25-second inactivity timeout and a 60-second overall timeout. HTTP is allowed for user-entered direct image addresses; HTTPS remains available and certificate validation is unchanged.

## Source layout

- `Sources/ImageSource.swift`: address parsing and user-facing errors.
- `Sources/ImageLoader.swift`: local and HTTP loading, bounded downloads, decoding, and cancellation.
- `Sources/main.swift`: native window, image canvas, menus, keyboard controls, and global shortcut.
- `scripts/`: build, installation, native app icon, and deterministic test fixtures.
