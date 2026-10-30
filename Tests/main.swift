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
print("\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
