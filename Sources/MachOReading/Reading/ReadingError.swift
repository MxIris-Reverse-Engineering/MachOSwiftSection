import MachOExtensions

package enum ReadingError: Error {
    case invalidDataSize
    case invalidLayoutSize
}

extension MachONamespace {
    func throwIfInvalid(_ isValid: Bool, error: ReadingError) throws {
        if !isValid {
            throw error
        }
    }
}
