import Foundation
import CrossReferenceAnalysis

/// `swift-section symbolicate`: what each unslid address is — inside which
/// function, a stub and where it leads, a pointer slot and what it holds, a
/// string, the nearest symbol — in a dyld shared cache or a set of files.
public struct SymbolicateRequest: Sendable, Equatable {
    public var input: CrossReferenceInput
    public var addresses: [UInt64]
    /// The image whose addresses these are, by path or file name: a set of
    /// standalone files each have their own addresses, and without it an
    /// address is read in the first file that maps it. A shared cache's
    /// images share theirs, and need none named.
    public var imageName: String?
    public var format: CrossReferenceOutputFormat

    public init(input: CrossReferenceInput, addresses: [UInt64], imageName: String? = nil, format: CrossReferenceOutputFormat = .text) {
        self.input = input
        self.addresses = addresses
        self.imageName = imageName
        self.format = format
    }

    /// Symbolicates the addresses, in order, delivers them, and returns them.
    @discardableResult
    public func run(output: some SwiftSectionOutput) async throws -> [AddressSymbolication] {
        let analyzer = try input.makeAnalyzer()
        let imageIndex = try imageName.map { name -> Int in
            // A name two images answer to — the macOS and the Mac Catalyst
            // variant — means the first; their addresses are apart.
            try analyzer.imageIndices(named: [name])[0]
        }
        let symbolications = addresses.map { analyzer.symbolication(of: $0, inImageAt: imageIndex) }
        let naming = CrossReferenceTargetNaming(analyzer: analyzer)
        switch format {
        case .text:
            for symbolication in symbolications {
                output.write(.text(Self.text(of: symbolication, naming: naming)))
            }
        case .json:
            let document = CrossReferenceJSONValue.object(["symbolications": .array(symbolications.map { Self.json(of: $0, naming: naming) })])
            output.write(.data(try document.encoded()))
        }
        return symbolications
    }

    private static func text(of symbolication: AddressSymbolication, naming: CrossReferenceTargetNaming) -> String {
        var columns = [CrossReferenceFormatting.hexadecimal(symbolication.address)]
        columns.append(symbolication.imagePath.map(CrossReferenceFormatting.imageName(ofPath:)) ?? "-")
        if let segmentName = symbolication.segmentName {
            columns.append(segmentName + (symbolication.sectionName.map { "," + $0 } ?? ""))
        } else {
            columns.append("-")
        }
        columns.append(meaningText(symbolication.meaning, naming: naming))
        return columns.joined(separator: "  ")
    }

    private static func meaningText(_ meaning: AddressSymbolication.Meaning, naming: CrossReferenceTargetNaming) -> String {
        switch meaning {
        case .function(let start, let name, let offset):
            let base = name ?? CrossReferenceFormatting.hexadecimal(start.address)
            return offset == 0 ? base : base + "+" + CrossReferenceFormatting.hexadecimal(offset)
        case .stub(let hops, let target):
            return "stub " + hops.map(CrossReferenceFormatting.hexadecimal).joined(separator: " -> ") + " -> " + naming.text(target)
        case .pointerSlot(let kind, let target):
            return "\(CrossReferenceFormatting.name(of: kind)) slot -> \(naming.text(target))"
        case .cString(let characters):
            return "C string \(CrossReferenceFormatting.quoted(characters))"
        case .constantString(let characters):
            return "CFString @\(CrossReferenceFormatting.quoted(characters))"
        case .symbol(let name, let offset):
            return offset == 0 ? name : name + "+" + CrossReferenceFormatting.hexadecimal(offset)
        case .data:
            return "data"
        case .unmapped:
            return "unmapped"
        }
    }

    private static func json(of symbolication: AddressSymbolication, naming: CrossReferenceTargetNaming) -> CrossReferenceJSONValue {
        .object([
            "address": .address(symbolication.address),
            "image": .optionalString(symbolication.imagePath),
            "segment": .optionalString(symbolication.segmentName),
            "section": .optionalString(symbolication.sectionName),
            "meaning": meaningJSON(symbolication.meaning, naming: naming),
        ])
    }

    private static func meaningJSON(_ meaning: AddressSymbolication.Meaning, naming: CrossReferenceTargetNaming) -> CrossReferenceJSONValue {
        switch meaning {
        case .function(let start, let name, let offset):
            return .object(["function": .object(["start": .address(start.address), "name": .optionalString(name), "offset": .address(offset)])])
        case .stub(let hops, let target):
            return .object(["stub": .object(["hops": .array(hops.map { .address($0) }), "target": naming.json(target)])])
        case .pointerSlot(let kind, let target):
            return .object(["pointerSlot": .object(["kind": .string(CrossReferenceFormatting.name(of: kind)), "target": naming.json(target)])])
        case .cString(let characters):
            return .object(["cString": .string(characters)])
        case .constantString(let characters):
            return .object(["constantString": .string(characters)])
        case .symbol(let name, let offset):
            return .object(["symbol": .object(["name": .string(name), "offset": .address(offset)])])
        case .data:
            return .object(["data": .object([:])])
        case .unmapped:
            return .object(["unmapped": .object([:])])
        }
    }
}
