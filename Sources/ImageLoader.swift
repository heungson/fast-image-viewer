import AppKit
import ImageIO

struct LoadedImage {
    let data: Data
    let width: Int
    let height: Int
    let format: String
}

final class ImageLoader: NSObject, URLSessionDataDelegate {
    static let byteLimit = 80 * 1024 * 1024
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var completion: ((Result<LoadedImage, Error>) -> Void)?
    private let lock = NSLock()
    private var cancelled = false

    func load(_ source: ImageSource, completion: @escaping (Result<LoadedImage, Error>) -> Void) {
        self.completion = completion
        if source.isLocal {
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let result = Result { () throws -> LoadedImage in
                    var directory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: source.url.path, isDirectory: &directory) else {
                        throw SourceError.missingFile
                    }
                    guard !directory.boolValue else { throw SourceError.directory }
                    let attributes = try FileManager.default.attributesOfItem(atPath: source.url.path)
                    guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= Self.byteLimit else {
                        throw SourceError.tooLarge
                    }
                    let data = try Data(contentsOf: source.url, options: .mappedIfSafe)
                    return try Self.decode(data)
                }
                finish(result)
            }
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 25
            config.timeoutIntervalForResource = 60
            config.urlCache = nil
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
            var request = URLRequest(url: source.url)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            task = session?.dataTask(with: request)
            task?.resume()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        completion = nil
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
    }

    private func finish(_ result: Result<LoadedImage, Error>) {
        lock.lock()
        let callback = cancelled ? nil : completion
        completion = nil
        lock.unlock()
        session?.finishTasksAndInvalidate()
        DispatchQueue.main.async { [self] in
            lock.lock()
            let deliver = !cancelled
            lock.unlock()
            if deliver { callback?(result) }
        }
    }

    static func decode(_ data: Data) throws -> LoadedImage {
        guard data.count <= byteLimit else { throw SourceError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw SourceError.notImage }
        guard Double(width) * Double(height) <= 120_000_000 else { throw SourceError.tooManyPixels }
        guard CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw SourceError.notImage }
        let type = CGImageSourceGetType(source) as String? ?? "image"
        let format = type.components(separatedBy: ".").last?.uppercased() ?? "IMAGE"
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        let swapsAxes = (5...8).contains(orientation)
        return LoadedImage(data: data, width: swapsAxes ? height : width, height: swapsAxes ? width : height, format: format)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            completionHandler(.cancel)
            finish(.failure(SourceError.http(http.statusCode)))
        } else if response.expectedContentLength > Int64(Self.byteLimit) {
            completionHandler(.cancel)
            finish(.failure(SourceError.tooLarge))
        } else {
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard buffer.count + data.count <= Self.byteLimit else {
            dataTask.cancel()
            finish(.failure(SourceError.tooLarge))
            return
        }
        buffer.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error { finish(.failure(error)); return }
        finish(Result { try Self.decode(buffer) })
    }
}
