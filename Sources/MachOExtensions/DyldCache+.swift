import Foundation
import MachOKit

extension DyldCache {
    package var mainCache: DyldCache? {
        if url.lastPathComponent.contains(".") {
            var url = url
            url.deletePathExtension()
            return try? .init(url: url)
        } else {
            return self
        }
    }
}
