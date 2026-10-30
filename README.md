# Fast Image Viewer

A small native macOS app for opening images from a pasted file path or a direct image URL. Built with Swift and AppKit; no Electron, web server, or third-party dependencies. The dark workspace puts the image first: an icon tool rail on the left, document information and Copy/Export actions in the header, and zoom controls below the canvas. Contextual controls show quick color swatches, custom colors, line widths, text sizes, or crop actions for the active tool. Lavender selection states, focus outlines, and hover feedback use a consistent visual style. The transparency checkerboard appears only behind the image.

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

Change or disable the global shortcut in **Fast Image Viewer → Global Shortcut**. Two alternate shortcuts are provided if another app uses the default. Left-click the menu bar photo icon to open the viewer directly. Right-click (or Control-click) it for the menu with **Open from Clipboard**, **Show Viewer**, and **Quit**.

Closing the window keeps the app running for its global shortcut. After quitting or restarting your Mac, open the app again to enable the shortcut. This app does not change your login items or default image viewer.

Fit mode preserves the aspect ratio and avoids enlarging small images. At **100%**, each image pixel uses one physical screen pixel, including on Retina screens. Large images can be scrolled; transparency appears over a checkerboard. Animated GIFs use the native image view.

## Edit and mark an image

The icon tool rail to the left of the preview includes **Pen**, **Arrow**, **Box**, **Oval**, **Text**, and **Crop**. Hover over an icon to see its name and keyboard shortcut. Pick a tool, then draw directly on the image. The cursor follows the active tool: a pen with its tip at the drawing point, an I-beam for text, or a precise target with an arrow, shape, or crop badge. Use a quick color swatch or the custom color well and set the line width before adding a mark. Text has a separate size control and appears where you click.

**Select** lets you move or delete individual marks: click a mark, drag it to move it, or press Delete to remove it. Dragging empty space in Select mode pans a zoomed image. The tool keys V, P, A, R, O, T, and C work while the image canvas has focus; they do not interrupt typing an address or text label.

For cropping, drag a rectangle and click **Apply Crop** or press Return. The rotate button turns the image 90° clockwise. Cropping and rotating flatten the current marks into the new bitmap; undo restores the previous editable marks.

- **Command–Z / Shift–Command–Z:** undo / redo edits. The toolbar undo buttons always affect image edits; keyboard undo affects text while a text field is focused.
- **Command–S / Export…:** save an edited copy as PNG or JPEG. The default name ends in `-edited.png`; choose `.jpg` for JPEG. PNG preserves transparency; JPEG uses a white background. Exporting to the original source filename is blocked.
- **Shift–Command–C:** copy the image, including all marks, to the clipboard as PNG.
- **Escape:** cancel a crop, selection, or active marking tool before hiding the window.

Edits are held in memory until exported. Opening a different image or quitting with unsaved edits offers **Keep Editing**, **Discard Edits**, or **Export…**. Closing the window preserves the current session. Animated images remain animated for viewing, but editing and exporting use the first frame. Undo retains up to 50 steps, with a memory budget for previous crop/rotation bitmaps.

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

Tests cover source parsing, paths with spaces, quotes and home expansion, file URLs, query preservation, decoding and metadata, missing files, folders, invalid data, HTTP downloads and errors, download size limits, and cancellation. Editor checks verify source-coordinate rendering, mark movement and deletion, undo/redo and saved revisions, top-left crop coordinates, clockwise rotation direction, orientation handling, PNG transparency, and JPEG output. The HTTP fixtures run only on loopback using Python 3’s standard library.

The live app was also checked with local paths, encoded file URLs, a public HTTPS WebP image, zooming, and missing-file feedback.

## Data handling and limits

Local images stay on your Mac. Web images are fetched only when you open an address, using an ephemeral network session without a persistent download cache. The app does not save image history, paths, clipboard contents, or telemetry. It stores the selected shortcut and window frame in macOS preferences.

Images use the formats supported by macOS ImageIO, including PNG, JPEG, HEIC, TIFF, GIF, BMP, and WebP on supported systems. The size limits are 80 MB and 120 megapixels. Network requests have a 25-second inactivity timeout and a 60-second overall timeout. HTTP is allowed for user-entered direct image addresses; HTTPS remains available and certificate validation is unchanged.

## Source layout

- `Sources/ImageSource.swift`: address parsing and user-facing errors.
- `Sources/ImageLoader.swift`: local and HTTP loading, bounded downloads, decoding, and cancellation.
- `Sources/ImageEditor.swift`: editable marks, image transformations, bounded undo history, rendering, and export.
- `Sources/EditorUI.swift`: editing toolbar, text labels, save/copy actions, and unsaved-edit prompts.
- `Sources/WindowLayout.swift`: compact window layout, address bar, canvas, and footer.
- `Sources/Appearance.swift`: shared button styles, icon tool picker, and app badge.
- `Sources/main.swift`: native window, image canvas, menus, keyboard controls, and global shortcut.
- `scripts/`: build, installation, native app icon, and deterministic test fixtures.
