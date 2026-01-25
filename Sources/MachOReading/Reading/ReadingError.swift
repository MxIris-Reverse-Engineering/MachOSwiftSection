import MachOExtensions

public enum ReadingError: Error {
    case invalidDataSize
    case invalidLayoutSize
    case invalidAddress(Int)
}

extension MachONamespace {
    func throwIfInvalid(_ isValid: Bool, error: ReadingError) throws {
        if !isValid {
            throw error
        }
    }
}
