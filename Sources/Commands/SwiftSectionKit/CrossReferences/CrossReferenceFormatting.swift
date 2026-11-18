import Foundation
import CrossReferenceAnalysis

/// A JSON value of a `refs` or `symbolicate` document. Addresses are always
/// hexadecimal strings, never numbers: a client parsing JSON numbers as
/// doubles loses the low bits of a 64-bit address.
enum CrossReferenceJSONValue: Encodable, Sendable, Hashable {
    case string(String)
    case integer(Int)
    case bool(Bool)
    case array([CrossReferenceJSONValue])
    case object([String: CrossReferenceJSONValue])
    case null

    static func address(_ value: UInt64) -> CrossReferenceJSONValue {
        .string(CrossReferenceFormatting.hexadecimal(value))
    }

    static func optionalString(_ value: String?) -> CrossReferenceJSONValue {
        value.map { .string($0) } ?? .null
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let values): try container.encode(values)
        case .object(let members): try container.encode(members)
        case .null: try container.encodeNil()
        }
    }

    /// The document's bytes: indented, keys sorted, so that two runs over the
    /// same input print the same bytes.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// How `refs` and `symbolicate` spell what they report, as text and as JSON.
/// The JSON names are a contract: renaming one is a breaking change of the
/// command line.
enum CrossReferenceFormatting {
    static func hexadecimal(_ value: UInt64) -> String {
        "0x" + String(value, radix: 16)
    }

    /// An image's file name, which the text rows show for its path.
    static func imageName(ofPath path: String) -> String {
        (path as NSString).lastPathComponent
    }

    static func name(of kind: CodeReferenceKind) -> String {
        switch kind {
        case .call: "call"
        case .tailCall: "tailCall"
        case .reference: "reference"
        }
    }

    static func name(of route: CodeReferenceRoute) -> String {
        switch route {
        case .direct: "direct"
        case .imageStub: "imageStub"
        case .stubIsland: "stubIsland"
        case .cacheSharedStub: "cacheSharedStub"
        case .pointerSlot: "pointerSlot"
        case .addressMaterialization: "addressMaterialization"
        case .literalLoad: "literalLoad"
        case .indirect: "indirect"
        }
    }

    static func name(of table: IndirectCallEvidence.Table) -> String {
        switch table {
        case .classVirtualTable: "classVirtualTable"
        case .protocolWitnessTable: "protocolWitnessTable"
        case .valueWitnessTable: "valueWitnessTable"
        case .none: "none"
        }
    }

    static func name(of slotKind: AddressSymbolication.PointerSlotKind) -> String {
        switch slotKind {
        case .globalOffsetTable: "globalOffsetTable"
        case .selectorReference: "selectorReference"
        case .classReference: "classReference"
        case .superclassReference: "superclassReference"
        case .protocolReference: "protocolReference"
        case .instanceVariableOffset: "instanceVariableOffset"
        }
    }

    /// `characters` in double quotes, with the characters that would break a
    /// line escaped.
    static func quoted(_ characters: String) -> String {
        var quoted = "\""
        for character in characters.unicodeScalars {
            switch character {
            case "\"": quoted += "\\\""
            case "\\": quoted += "\\\\"
            case "\n": quoted += "\\n"
            case "\r": quoted += "\\r"
            case "\t": quoted += "\\t"
            default: quoted.unicodeScalars.append(character)
            }
        }
        return quoted + "\""
    }
}

/// Names what references point at, for one request: the functions are looked
/// up in one pass over their images (``prepareFunctions(at:)``), the Swift
/// types as they come.
final class CrossReferenceTargetNaming {
    let analyzer: CrossReferenceAnalyzer
    private var functionsByLocation: [CodeLocation: CodeFunction] = [:]
    private var swiftTypeKeysByLocation: [CodeLocation: String?] = [:]

    init(analyzer: CrossReferenceAnalyzer) {
        self.analyzer = analyzer
    }

    /// Looks up the functions at `locations` together, each image's function
    /// table built for the lookup and dropped.
    func prepareFunctions(at locations: some Sequence<CodeLocation>) {
        let missing = Set(locations).subtracting(functionsByLocation.keys)
        guard !missing.isEmpty else { return }
        functionsByLocation.merge(analyzer.functions(containing: missing)) { existing, _ in existing }
    }

    func function(at location: CodeLocation) -> CodeFunction? {
        if let function = functionsByLocation[location] { return function }
        prepareFunctions(at: [location])
        return functionsByLocation[location]
    }

    func imagePath(of location: CodeLocation) -> String {
        analyzer.imagePaths[location.imageIndex]
    }

    /// The name of the function at `location`, or its address when nothing
    /// names it — with the offset of `address` into it, when that is not its
    /// first instruction.
    func functionText(at location: CodeLocation, address: UInt64? = nil) -> String {
        let base = function(at: location)?.name?.spelling ?? CrossReferenceFormatting.hexadecimal(location.address)
        guard let address, address > location.address else { return base }
        return base + "+" + CrossReferenceFormatting.hexadecimal(address - location.address)
    }

    private func swiftTypeKey(at location: CodeLocation) -> String? {
        if let key = swiftTypeKeysByLocation[location] { return key }
        let key = analyzer.swiftTypeIdentity(ofDescriptorAt: location)?.key
        swiftTypeKeysByLocation[location] = key
        return key
    }

    private func locationJSON(_ location: CodeLocation) -> [String: CrossReferenceJSONValue] {
        ["image": .string(imagePath(of: location)), "address": .address(location.address)]
    }

    func json(_ target: CodeReferenceTarget) -> CrossReferenceJSONValue {
        switch target {
        case .function(let location):
            var members = locationJSON(location)
            members["name"] = .optionalString(function(at: location)?.name?.spelling)
            return .object(["function": .object(members)])
        case .importedSymbol(let name):
            return .object(["importedSymbol": .string(name)])
        case .messageSend(let selector, let receiver):
            var members: [String: CrossReferenceJSONValue] = ["selector": .string(selector)]
            switch receiver {
            case .methodReceiver: members["receiver"] = .string("methodReceiver")
            case .classLiteral(let className):
                members["receiver"] = .string("classLiteral")
                members["receiverClass"] = .string(className)
            case .unknown: members["receiver"] = .string("unknown")
            }
            return .object(["messageSend": .object(members)])
        case .superMessageSend(let selector, let className):
            return .object(["superMessageSend": .object(["selector": .string(selector), "class": .optionalString(className)])])
        case .swiftType(let descriptor):
            var members = locationJSON(descriptor)
            members["key"] = .optionalString(swiftTypeKey(at: descriptor))
            return .object(["swiftType": .object(members)])
        case .swiftTypeName(.mangledName(let location, let length)):
            var members = locationJSON(location)
            members["length"] = .integer(length)
            return .object(["swiftTypeName": .object(members)])
        case .swiftTypeName(.accessorSymbol(let symbol)):
            return .object(["swiftTypeName": .object(["accessorSymbol": .string(symbol)])])
        case .objectiveCClass(let name, let location):
            var members = locationJSON(location)
            members["name"] = .string(name)
            return .object(["objectiveCClass": .object(members)])
        case .objectiveCInstanceVariable(let className, let name):
            return .object(["instanceVariable": .object(["class": .string(className), "name": .string(name)])])
        case .cString(let characters):
            return .object(["cString": .string(characters)])
        case .constantString(let characters):
            return .object(["constantString": .string(characters)])
        case .indirect(let evidence):
            return .object(["indirect": .object([
                "table": .string(CrossReferenceFormatting.name(of: evidence.table)),
                "tableOffset": evidence.tableOffset.map { .integer(Int($0)) } ?? .null,
                "pointerAuthenticationConstant": evidence.pointerAuthenticationConstant.map { .address(UInt64($0)) } ?? .null,
                "isAddressBlended": .bool(evidence.isAddressBlended),
            ])])
        case .unrecognized(let address):
            return .object(["unrecognized": .address(address)])
        }
    }

    func text(_ target: CodeReferenceTarget) -> String {
        switch target {
        case .function(let location):
            return "\(functionText(at: location)) (\(CrossReferenceFormatting.imageName(ofPath: imagePath(of: location))))"
        case .importedSymbol(let name):
            return "\(name) (imported)"
        case .messageSend(let selector, let receiver):
            switch receiver {
            case .methodReceiver: return "send \(selector) to self"
            case .classLiteral(let className): return "send \(selector) to \(className)"
            case .unknown: return "send \(selector)"
            }
        case .superMessageSend(let selector, let className):
            return "send super \(selector)" + (className.map { " above \($0)" } ?? "")
        case .swiftType(let descriptor):
            let name = swiftTypeKey(at: descriptor) ?? CrossReferenceFormatting.hexadecimal(descriptor.address)
            return "type \(name) (\(CrossReferenceFormatting.imageName(ofPath: imagePath(of: descriptor))))"
        case .swiftTypeName(.mangledName(let location, let length)):
            return "type name at \(CrossReferenceFormatting.hexadecimal(location.address)), \(length) bytes (\(CrossReferenceFormatting.imageName(ofPath: imagePath(of: location))))"
        case .swiftTypeName(.accessorSymbol(let symbol)):
            return "type accessor \(symbol)"
        case .objectiveCClass(let name, let location):
            return "class \(name) (\(CrossReferenceFormatting.imageName(ofPath: imagePath(of: location))))"
        case .objectiveCInstanceVariable(let className, let name):
            return "ivar \(className).\(name)"
        case .cString(let characters):
            return "C string \(CrossReferenceFormatting.quoted(characters))"
        case .constantString(let characters):
            return "CFString @\(CrossReferenceFormatting.quoted(characters))"
        case .indirect(let evidence):
            var text = "indirect"
            if evidence.table != IndirectCallEvidence.Table.none { text += " through \(CrossReferenceFormatting.name(of: evidence.table))" }
            if let tableOffset = evidence.tableOffset { text += " at offset \(tableOffset)" }
            return text
        case .unrecognized(let address):
            return "unrecognized \(CrossReferenceFormatting.hexadecimal(address))"
        }
    }
}
