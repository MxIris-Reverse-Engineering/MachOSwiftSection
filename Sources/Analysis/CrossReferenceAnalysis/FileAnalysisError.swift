@_spi(Internals) import MachOCodeReferences

extension CrossReferenceAnalyzer {
    /// Why an analyzer could not be made from files.
    public struct FileAnalysisError: Error, Hashable, Sendable {
        /// What went wrong. More codes may come.
        public struct Code: Hashable, Sendable {
            private let name: String

            /// The cache or the file holds no arm64 code: the analysis reads
            /// arm64 and arm64e machine code only.
            public static let unsupportedArchitecture = Code(name: "unsupportedArchitecture")
        }

        public let code: Code
        /// The file the error is about.
        public let path: String
    }
}
