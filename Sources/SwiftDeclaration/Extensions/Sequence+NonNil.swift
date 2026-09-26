extension Sequence {
    package func filterNonNil<T, E: Swift.Error>(_ filter: (Element) throws(E) -> T?) throws(E) -> [Element] {
        var results: [Element] = []
        for element in self {
            if try filter(element) != nil {
                results.append(element)
            }
        }
        return results
    }

    package func firstNonNil<T, E: Swift.Error>(_ transform: (Element) throws(E) -> T?) throws(E) -> T? {
        for element in self {
            if let newElement = try transform(element) {
                return newElement
            }
        }
        return nil
    }

    package func asyncFirstNonNil<T, E: Swift.Error>(_ transform: (Element) async throws(E) -> T?) async throws(E) -> T? {
        for element in self {
            if let newElement = try await transform(element) {
                return newElement
            }
        }
        return nil
    }
}
