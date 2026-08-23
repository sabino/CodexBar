import CodexBarCore
import Foundation
import SwiftCrossUI

@MainActor
enum ProviderIconStore {
    private static var cachedURLs: [String: URL] = [:]

    static func url(for provider: UsageProvider) -> URL? {
        let resourceName = ProviderDescriptorRegistry.descriptor(for: provider).branding.iconResourceName
        if let cached = self.cachedURLs[resourceName] {
            return cached
        }
        guard let encoded = GeneratedProviderIconData.pngBase64ByResourceName[resourceName],
              let data = Data(base64Encoded: encoded)
        else { return nil }

        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("CodexBar/provider-icons-v1", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBar/provider-icons-v1", isDirectory: true)
        let url = directory.appendingPathComponent(resourceName).appendingPathExtension("png")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try data.write(to: url, options: .atomic)
            }
            self.cachedURLs[resourceName] = url
            return url
        } catch {
            return nil
        }
    }
}

struct ProviderArtwork: View {
    let provider: UsageProvider
    var fallback: String = "◇"

    var body: some View {
        if let url = ProviderIconStore.url(for: self.provider) {
            Image(url)
                .resizable()
        } else {
            Text(self.fallback)
        }
    }
}
