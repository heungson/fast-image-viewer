import Foundation

enum SourceError: LocalizedError {
    case empty, invalidAddress, unsupportedScheme, missingFile, directory, tooLarge, notImage, tooManyPixels
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .empty: return "Paste an image path or URL to get started."
        case .invalidAddress: return "Use an absolute file path, a file:// address, or an http(s) image URL."
        case .unsupportedScheme: return "This address type isn’t supported. Use a file path or an http(s) image URL."
        case .missingFile: return "That file couldn’t be found. Check the path; temporary screenshots may have been deleted."
        case .directory: return "That path is a folder. Choose an image file inside it."
        case .tooLarge: return "This image is too large to open. The file size limit is 80 MB."
        case .notImage: return "This file couldn’t be read as an image. For web images, paste the direct image URL."
        case .tooManyPixels: return "This image is too large to display. Try an image smaller than 120 megapixels."
        case .http(let code): return "The server returned HTTP \(code). Check the URL or try downloading the image first."
        }
    }
}

struct ImageSource: Equatable {
    let url: URL
    var isLocal: Bool { url.isFileURL }
    var address: String { isLocal ? url.path : url.absoluteString }
    var name: String { url.lastPathComponent.isEmpty ? (url.host ?? "Image") : url.lastPathComponent }

    static func parse(_ input: String) throws -> ImageSource {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw SourceError.empty }
        if value.count >= 2, let first = value.first, let last = value.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            value = String(value.dropFirst().dropLast())
        }
        if value.hasPrefix("/") || value.hasPrefix("~/") {
            // Finder paths and terminal-dragged paths both work; never evaluate shell text.
            var path = ""
            var index = value.startIndex
            while index < value.endIndex {
                let char = value[index]
                let next = value.index(after: index)
                if char == "\\", next < value.endIndex, " ()[]{}#'\"\\".contains(value[next]) {
                    path.append(value[next])
                    index = value.index(after: next)
                } else {
                    path.append(char)
                    index = next
                }
            }
            return ImageSource(url: URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL)
        }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else {
            throw SourceError.invalidAddress
        }
        switch scheme {
        case "file":
            guard url.host == nil || url.host == "" || url.host == "localhost", url.path.hasPrefix("/") else {
                throw SourceError.invalidAddress
            }
            return ImageSource(url: URL(fileURLWithPath: url.path).standardizedFileURL)
        case "http", "https":
            guard let host = url.host, !host.isEmpty else { throw SourceError.invalidAddress }
            return ImageSource(url: url)
        default: throw SourceError.unsupportedScheme
        }
    }
}
