import Foundation

enum CrossTrayIconState: String, Equatable {
    case loading
    case green = "quota-green"
    case amber = "quota-amber"
    case red = "quota-red"
    case error
}

@MainActor
enum TrayIconStore {
    private static var cachedURLs: [CrossTrayIconState: URL] = [:]

    static func url(for state: CrossTrayIconState) -> URL? {
        if let cached = self.cachedURLs[state] {
            return cached
        }
        #if os(Windows)
        let encoded = GeneratedTrayIconData.icoBase64ByName[state.rawValue]
        let fileExtension = "ico"
        #else
        let encoded = GeneratedTrayIconData.pngBase64ByName[state.rawValue]
        let fileExtension = "png"
        #endif
        guard let encoded, let data = Data(base64Encoded: encoded) else { return nil }

        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("CodexBar/tray-icons-v1", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBar/tray-icons-v1", isDirectory: true)
        let url = directory.appendingPathComponent(state.rawValue).appendingPathExtension(fileExtension)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try data.write(to: url, options: .atomic)
            }
            self.cachedURLs[state] = url
            return url
        } catch {
            return nil
        }
    }
}
