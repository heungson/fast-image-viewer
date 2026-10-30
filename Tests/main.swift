import Foundation
import AppKit
import ImageIO

var failures = 0
var checks = 0
func check(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition { failures += 1; print("FAIL: \(message)") }
}
func rejects(_ value: String) {
    do { _ = try ImageSource.parse(value); check(false, "Should reject \(value)") }
    catch { check(true, "Rejected") }
}

do {
    check(try ImageSource.parse(" /tmp/a b.png\n").url.path == "/tmp/a b.png", "Whitespace around file path")
    check(try ImageSource.parse("\"/tmp/a b.png\"").url.path == "/tmp/a b.png", "Quoted file path")
    check(try ImageSource.parse("'/tmp/a b.png'").url.path == "/tmp/a b.png", "Single quoted path")
    check(try ImageSource.parse("/tmp/a\\ b\\(2\\).png").url.path == "/tmp/a b(2).png", "Terminal escaped path")
    check(try ImageSource.parse("~/Pictures/image.png").url.path == NSHomeDirectory() + "/Pictures/image.png", "Home directory expansion")
    check(try ImageSource.parse("file:///tmp/a%20b%23c.png").url.path == "/tmp/a b#c.png", "Encoded file URL")
    check(try ImageSource.parse("file://localhost/tmp/a.png").url.path == "/tmp/a.png", "Localhost file URL")
    check(try ImageSource.parse("/tmp/a%20b.png").url.path == "/tmp/a%20b.png", "Literal percent in file path")
    check(try ImageSource.parse("https://example.com/a.png?token=a%2Fb#image").address == "https://example.com/a.png?token=a%2Fb#image", "URL query preserved")
    check(try ImageSource.parse("http://127.0.0.1:9876/image.png").isLocal == false, "HTTP source")
} catch { check(false, "Unexpected parsing error: \(error)") }
for value in ["", "   ", "image.png", "javascript:alert(1)", "ftp://example.com/a.png", "file://remote/tmp/image.png", "https://"] { rejects(value) }

let temp = FileManager.default.temporaryDirectory.appendingPathComponent("fast-image-viewer-tests-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temp) }

// A real PNG fixture exercises metadata extraction and image decoding.
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 360, bitsPerSample: 8,
                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
let png = bitmap.representation(using: .png, properties: [:])!
let imageURL = temp.appendingPathComponent("test image.png")
try png.write(to: imageURL)
let loaded = try ImageLoader.decode(png)
check(loaded.width == 640 && loaded.height == 360, "Image dimensions")
check(loaded.format == "PNG", "Image format")
let jpeg = NSMutableData()
let destination = CGImageDestinationCreateWithData(jpeg, "public.jpeg" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, bitmap.cgImage!, [kCGImagePropertyOrientation: 6] as CFDictionary)
check(CGImageDestinationFinalize(destination), "JPEG fixture encoding")
let rotated = try ImageLoader.decode(jpeg as Data)
check(rotated.width == 360 && rotated.height == 640, "EXIF rotation adjusts image dimensions")
do { _ = try ImageLoader.decode(Data("not an image".utf8)); check(false, "Reject non-image bytes") }
catch { check(true, "Rejected non-image bytes") }

func awaitLoad(_ source: ImageSource) -> Result<LoadedImage, Error> {
    let loader = ImageLoader()
    var result: Result<LoadedImage, Error>?
    loader.load(source) { result = $0 }
    let deadline = Date().addingTimeInterval(8)
    while result == nil && Date() < deadline { _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
    loader.cancel()
    return result ?? .failure(NSError(domain: "TestTimeout", code: 1))
}
switch awaitLoad(ImageSource(url: imageURL)) {
case .success(let image): check(image.width == 640, "Local image loading")
case .failure(let error): check(false, "Local loading: \(error)")
}
switch awaitLoad(ImageSource(url: temp.appendingPathComponent("missing.png"))) {
case .success: check(false, "Missing file rejected")
case .failure(let error): check(error is SourceError, "Missing file error")
}
switch awaitLoad(ImageSource(url: temp)) {
case .success: check(false, "Folder rejected")
case .failure(let error): check(error is SourceError, "Folder error")
}
let invalidURL = temp.appendingPathComponent("bad.png")
try Data("not an image".utf8).write(to: invalidURL)
switch awaitLoad(ImageSource(url: invalidURL)) {
case .success: check(false, "Non-image file rejected")
case .failure(let error): check(error is SourceError, "Non-image error")
}
let bigURL = temp.appendingPathComponent("large.png")
FileManager.default.createFile(atPath: bigURL.path, contents: nil)
let handle = try FileHandle(forWritingTo: bigURL)
try handle.truncate(atOffset: UInt64(ImageLoader.byteLimit + 1))
try handle.close()
switch awaitLoad(ImageSource(url: bigURL)) {
case .success: check(false, "Oversized local file rejected")
case .failure(let error): check(error is SourceError, "Local byte limit checked before reading")
}

if let base = ProcessInfo.processInfo.environment["TEST_SERVER_URL"] {
    switch awaitLoad(try ImageSource.parse(base + "/image.png")) {
    case .success(let image): check(image.width == 640 && image.height == 360, "HTTP image download")
    case .failure(let error): check(false, "HTTP download: \(error)")
    }
    for route in ["/not-found", "/invalid", "/oversized", "/oversized-stream"] {
        switch awaitLoad(try ImageSource.parse(base + route)) {
        case .success: check(false, "HTTP should reject \(route)")
        case .failure(let error): check(error is SourceError, "HTTP rejection for \(route): \(error)")
        }
    }
    // Cancellation must suppress completion, even if another image opens immediately.
    let loader = ImageLoader()
    var called = false
    loader.load(try ImageSource.parse(base + "/slow")) { _ in called = true }
    loader.cancel()
    let until = Date().addingTimeInterval(0.25)
    while Date() < until { _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
    check(!called, "Cancelled request does not replace the current image")
}
// Use distinct top/bottom colors to detect flipped crops and rotations, not just size changes.
let context = try ImageEditor.context(width: 100, height: 60)
context.setFillColor(NSColor.blue.cgColor); context.fill(CGRect(x: 0, y: 0, width: 100, height: 60))
context.setFillColor(NSColor.green.cgColor); context.fill(CGRect(x: 0, y: 30, width: 100, height: 30))
let baseImage = context.makeImage()!
func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
    let normalized = try ImageEditor.context(width: image.width, height: image.height)
    normalized.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let data = normalized.data!.assumingMemoryBound(to: UInt8.self)
    let offset = y * normalized.bytesPerRow + x * 4
    return Array(UnsafeBufferPointer(start: data + offset, count: 4))
}
let editor = ImageEditor(image: baseImage)
check(!editor.isDirty && !editor.canUndo, "Fresh editor has no unsaved changes")
let box = ImageMark(tool: .rectangle, points: [CGPoint(x: 10, y: 10), CGPoint(x: 80, y: 45)], color: .red, width: 4)
editor.add(box)
check(editor.isDirty && editor.canUndo, "Adding a mark is undoable and dirty")
let markedImage = try ImageEditor.render(editor.state)
let edge = try pixel(markedImage, x: 10, y: 20)
check(edge[0] > 240 && edge[1] < 10 && edge[2] < 10, "Marks are rendered at source pixel coordinates")
editor.undo()
check(!editor.isDirty && editor.state.marks.isEmpty && editor.canRedo, "Undo restores original and clean state")
editor.redo()
check(editor.state.marks.count == 1 && editor.isDirty, "Redo restores marks")
let savedRevision = editor.state.id
editor.markExported(savedRevision)
check(!editor.isDirty, "Exported revision is clean")
editor.replaceMark(at: 0, with: box.moved(by: CGPoint(x: 2, y: 3)))
check(editor.state.marks[0].points[0] == CGPoint(x: 12, y: 13) && editor.isDirty, "Marks can move independently")
editor.undo(); check(!editor.isDirty, "Undo to exported revision is clean")
editor.removeMark(at: 0); check(editor.state.marks.isEmpty, "Selected mark can be deleted")
editor.undo(); check(editor.state.marks.count == 1, "Delete can be undone")

let cropEditor = ImageEditor(image: baseImage)
try cropEditor.crop(to: CGRect(x: 5, y: 3, width: 20, height: 15))
check(cropEditor.state.base.width == 20 && cropEditor.state.base.height == 15, "Crop dimensions")
let topPixel = try pixel(cropEditor.state.base, x: 5, y: 5)
check(topPixel[1] > 240 && topPixel[2] < 10, "Crop uses the top-left image coordinate system")
cropEditor.undo()
check(cropEditor.state.base.width == 100 && !cropEditor.isDirty, "Crop undo restores full image")
do { try cropEditor.crop(to: CGRect(x: -20, y: -20, width: 2, height: 2)); check(false, "Reject outside crop") }
catch { check(true, "Outside crop rejected") }
do { try cropEditor.crop(to: CGRect(x: 5, y: 5, width: 1, height: 1)); check(false, "Reject tiny crop") }
catch { check(true, "Tiny crop rejected") }
try cropEditor.rotateClockwise()
check(cropEditor.state.base.width == 60 && cropEditor.state.base.height == 100, "Rotate swaps dimensions")
let right = try pixel(cropEditor.state.base, x: 50, y: 50)
let left = try pixel(cropEditor.state.base, x: 10, y: 50)
check(right[1] > 240 && left[2] > 240, "Clockwise rotation places original top edge on the right")
cropEditor.undo()
check(cropEditor.state.base.width == 100 && !cropEditor.isDirty, "Rotate undo restores original")

let transparent = try ImageEditor.context(width: 40, height: 30).makeImage()!
let transparentEditor = ImageEditor(image: transparent)
let transparentPNG = try ImageEditor.export(transparentEditor.state)
let decodedPNG = try ImageEditor(data: transparentPNG, maxDimension: 40)
check(try pixel(decodedPNG.state.base, x: 10, y: 10)[3] == 0, "PNG preserves transparency")
let opaqueJPEG = try ImageEditor.export(transparentEditor.state, jpeg: true)
let decodedJPEG = try ImageEditor(data: opaqueJPEG, maxDimension: 40)
let white = try pixel(decodedJPEG.state.base, x: 10, y: 10)
check(white[0] > 240 && white[1] > 240 && white[2] > 240, "JPEG flattens transparency onto white")
let arrowEditor = ImageEditor(image: transparent)
arrowEditor.add(ImageMark(tool: .arrow, points: [CGPoint(x: 5, y: 5), CGPoint(x: 32, y: 23)], color: .red, width: 2))
let arrowPNG = try ImageEditor.export(arrowEditor.state)
check(try ImageLoader.decode(arrowPNG).width == 40, "Arrow export produces valid image data")
let orientedEditor = try ImageEditor(data: jpeg as Data, maxDimension: 640)
check(orientedEditor.state.base.width == 360 && orientedEditor.state.base.height == 640, "Editor normalizes EXIF orientation")

print("\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
