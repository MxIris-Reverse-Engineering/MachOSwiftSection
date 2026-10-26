import Foundation

/// One image's references, filed by what they reference and stored small
/// enough for a host to keep for every image it has open: a name is stored
/// once however many references carry it, and the referencing function and
/// instruction as 32-bit offsets into the image's `__text`.
///
/// It holds what a query for callers or for a type's references reads —
/// calls and tail calls, sends, imported names, class and Swift type
/// references — and leaves out indirect calls and branches into no image.
/// Read from it, ``references(to:)`` answers exactly what
/// ``CrossReferenceAnalyzer/references(to:inImageAt:)`` scans for, and
/// ``CrossReferenceAnalyzer/references(toSwiftType:in:)`` what
/// ``CrossReferenceAnalyzer/references(toSwiftType:inImageAt:)`` does.
///
/// A value that holds no analyzer: any analyzer over the same images reads
/// it, so a host may replace its analyzer and keep its indexes, as long as
/// the image keeps its position. Built by
/// ``CrossReferenceAnalyzer/referenceIndex(ofImageAt:)``.
public struct CodeReferenceIndex: Sendable {
    /// One reference, without what it references: its group says that.
    struct Entry {
        let functionOffset: UInt32
        let instructionOffset: UInt32
        /// For a send, the class-literal receiver; for a super send, the
        /// class the lookup starts above: a position in `classNames`, plus
        /// one. Zero for none.
        let className: UInt32
        /// Bits 0–1 the kind, bit 2 a runtime helper call, bits 3–4 how a
        /// send's receiver is known.
        let flags: UInt8
    }

    /// What every reference of a group references, but a send's receiver,
    /// which its entry carries.
    enum Target: Hashable {
        case function(CodeLocation)
        case importedSymbol(name: String)
        case messageSend(selector: String)
        case superMessageSend(selector: String)
        case objectiveCClass(name: String, location: CodeLocation)
        case swiftType(descriptor: CodeLocation)
        case swiftTypeName(SwiftTypeName)
    }

    struct Group {
        let target: Target
        let entryStart: Int32
        let entryEnd: Int32
    }

    /// The image's position in the analyzer's
    /// ``CrossReferenceAnalyzer/images``.
    public let imageIndex: Int

    /// A rough measure of the memory the index holds, the heap storage of its
    /// names included.
    public let approximateByteCount: Int

    /// Where the offsets count from: the start of the image's `__text`.
    private let codeStart: UInt64
    /// Every group's entries, one group after another, each in scan order.
    private let entries: [Entry]
    /// Groups sharing a table key lie next to each other — a selector's sends
    /// and super sends, a class name's classes — and the Swift type and type
    /// name groups, which a type query reads through, last.
    private let groups: [Group]
    private let groupRangesByKey: [CodeReferenceTable.Key: Range<Int32>]
    private let swiftTypeGroupRange: Range<Int32>
    private let swiftTypeNameGroupRange: Range<Int32>
    private let classNames: [String]

    /// How many references the index holds.
    public var referenceCount: Int {
        entries.count
    }

    /// The references filed under any of `keys`, in instruction order — what
    /// ``CrossReferenceAnalyzer/references(to:inImageAt:)`` finds for them.
    public func references(to keys: Set<CodeReferenceTable.Key>) -> [CodeReference] {
        var groupIndices: [Int32] = []
        for key in keys {
            guard let range = groupRangesByKey[key] else { continue }
            groupIndices.append(contentsOf: range)
        }
        return references(inGroupsAt: groupIndices)
    }

    /// The references in the groups a type query reads — every Swift type and
    /// type name, and the classes named `objectiveCClassName` — whose target
    /// `matches`.
    func references(toTypesMatching matches: (CodeReferenceTarget) -> Bool, objectiveCClassName: String?) -> [CodeReference] {
        var candidateGroups = Array(swiftTypeGroupRange) + Array(swiftTypeNameGroupRange)
        if let objectiveCClassName, let range = groupRangesByKey[.objectiveCClass(objectiveCClassName)] {
            candidateGroups.append(contentsOf: range)
        }
        return references(inGroupsAt: candidateGroups.filter { matches(Self.target(of: groups[Int($0)].target, receiver: .unknown, className: nil)) })
    }

    /// The references of the groups, in instruction order: a call before the
    /// type reference it also makes, as a scan records them.
    private func references(inGroupsAt groupIndices: [Int32]) -> [CodeReference] {
        var positions: [(entryIndex: Int32, groupIndex: Int32)] = []
        for groupIndex in groupIndices {
            let group = groups[Int(groupIndex)]
            for entryIndex in group.entryStart ..< group.entryEnd {
                positions.append((entryIndex, groupIndex))
            }
        }
        positions.sort { left, right in
            let leftEntry = entries[Int(left.entryIndex)]
            let rightEntry = entries[Int(right.entryIndex)]
            if leftEntry.instructionOffset != rightEntry.instructionOffset { return leftEntry.instructionOffset < rightEntry.instructionOffset }
            let leftRank = Self.kindRank(leftEntry.flags)
            let rightRank = Self.kindRank(rightEntry.flags)
            if leftRank != rightRank { return leftRank < rightRank }
            if left.groupIndex != right.groupIndex { return left.groupIndex < right.groupIndex }
            return left.entryIndex < right.entryIndex
        }
        return positions.map { reference(at: Int($0.entryIndex), in: groups[Int($0.groupIndex)]) }
    }

    private func reference(at entryIndex: Int, in group: Group) -> CodeReference {
        let entry = entries[entryIndex]
        let className = entry.className == 0 ? nil : classNames[Int(entry.className - 1)]
        let receiver: ReceiverClassHint
        switch (entry.flags >> 3) & 0b11 {
        case 1:
            receiver = .methodReceiver
        case 2:
            receiver = .classLiteral(className ?? "")
        default:
            receiver = .unknown
        }
        return CodeReference(
            function: CodeLocation(imageIndex: imageIndex, address: codeStart + UInt64(entry.functionOffset)),
            instructionAddress: codeStart + UInt64(entry.instructionOffset),
            kind: Self.kind(entry.flags),
            target: Self.target(of: group.target, receiver: receiver, className: className),
            isRuntimeHelperCall: entry.flags & 0b100 != 0
        )
    }

    private static func target(of target: Target, receiver: ReceiverClassHint, className: String?) -> CodeReferenceTarget {
        switch target {
        case .function(let location):
            return .function(location)
        case .importedSymbol(let name):
            return .importedSymbol(name: name)
        case .messageSend(let selector):
            return .messageSend(selector: selector, receiver: receiver)
        case .superMessageSend(let selector):
            return .superMessageSend(selector: selector, className: className)
        case .objectiveCClass(let name, let location):
            return .objectiveCClass(name: name, location: location)
        case .swiftType(let descriptor):
            return .swiftType(descriptor: descriptor)
        case .swiftTypeName(let name):
            return .swiftTypeName(name)
        }
    }

    private static func kind(_ flags: UInt8) -> CodeReference.Kind {
        switch flags & 0b11 {
        case 1: .tailCall
        case 2: .reference
        default: .call
        }
    }

    /// A call or tail call comes before the type reference the same
    /// instruction makes.
    private static func kindRank(_ flags: UInt8) -> UInt8 {
        flags & 0b11 == 2 ? 1 : 0
    }

    // MARK: - Building

    /// Files a scan's references as they come, function by function.
    struct Builder {
        private let imageIndex: Int
        private let codeStart: UInt64
        private var entriesByTarget: [Target: [Entry]] = [:]
        private var classNamePositions: [String: UInt32] = [:]
        private var classNames: [String] = []

        init(imageIndex: Int, codeStart: UInt64) {
            self.imageIndex = imageIndex
            self.codeStart = codeStart
        }

        mutating func add(_ reference: CodeReference) {
            let target: Target
            var className: String?
            var receiverBits: UInt8 = 0
            switch reference.target {
            case .function(let location):
                target = .function(location)
            case .importedSymbol(let name):
                target = .importedSymbol(name: name)
            case .messageSend(let selector, let receiver):
                target = .messageSend(selector: selector)
                switch receiver {
                case .methodReceiver:
                    receiverBits = 1
                case .classLiteral(let name):
                    receiverBits = 2
                    className = name
                case .unknown:
                    receiverBits = 0
                }
            case .superMessageSend(let selector, let superclassName):
                target = .superMessageSend(selector: selector)
                className = superclassName
            case .objectiveCClass(let name, let location):
                target = .objectiveCClass(name: name, location: location)
            case .swiftType(let descriptor):
                target = .swiftType(descriptor: descriptor)
            case .swiftTypeName(let name):
                target = .swiftTypeName(name)
            case .indirect, .unrecognized:
                // No query for callers or for a type reads them.
                return
            }
            let kindBits: UInt8
            switch reference.kind {
            case .call: kindBits = 0
            case .tailCall: kindBits = 1
            case .reference: kindBits = 2
            }
            assert(
                reference.function.address >= codeStart && reference.instructionAddress >= codeStart && reference.instructionAddress - codeStart <= UInt64(UInt32.max),
                "a reference outside the image's __text"
            )
            var classNamePosition: UInt32 = 0
            if let className {
                classNamePosition = position(ofClassName: className)
            }
            let entry = Entry(
                functionOffset: UInt32(truncatingIfNeeded: reference.function.address &- codeStart),
                instructionOffset: UInt32(truncatingIfNeeded: reference.instructionAddress &- codeStart),
                className: classNamePosition,
                flags: kindBits | (reference.isRuntimeHelperCall ? 0b100 : 0) | (receiverBits << 3)
            )
            entriesByTarget[target, default: []].append(entry)
        }

        private mutating func position(ofClassName name: String) -> UInt32 {
            if let position = classNamePositions[name] { return position }
            classNames.append(name)
            let position = UInt32(classNames.count)
            classNamePositions[name] = position
            return position
        }

        /// Lays the groups out — those sharing a key next to each other, the
        /// Swift type and type name groups last — and files them by key.
        func index() -> CodeReferenceIndex {
            var keyedTargets: [CodeReferenceTable.Key: [Target]] = [:]
            var swiftTypeTargets: [Target] = []
            var swiftTypeNameTargets: [Target] = []
            for target in entriesByTarget.keys {
                switch target {
                case .function(let location):
                    keyedTargets[.function(location), default: []].append(target)
                case .importedSymbol(let name):
                    keyedTargets[.importedSymbol(name), default: []].append(target)
                case .messageSend(let selector), .superMessageSend(let selector):
                    keyedTargets[.selector(selector), default: []].append(target)
                case .objectiveCClass(let name, _):
                    keyedTargets[.objectiveCClass(name), default: []].append(target)
                case .swiftType:
                    swiftTypeTargets.append(target)
                case .swiftTypeName:
                    swiftTypeNameTargets.append(target)
                }
            }
            var entries: [Entry] = []
            entries.reserveCapacity(entriesByTarget.values.reduce(0) { $0 + $1.count })
            var groups: [Group] = []
            var nameBytes = 0
            func appendGroup(_ target: Target) {
                let targetEntries = entriesByTarget[target] ?? []
                let start = Int32(entries.count)
                entries.append(contentsOf: targetEntries)
                groups.append(Group(target: target, entryStart: start, entryEnd: Int32(entries.count)))
                nameBytes += Self.heapByteCount(of: target)
            }
            var groupRangesByKey: [CodeReferenceTable.Key: Range<Int32>] = [:]
            groupRangesByKey.reserveCapacity(keyedTargets.count + swiftTypeTargets.count)
            for (key, targets) in keyedTargets {
                let start = Int32(groups.count)
                targets.forEach(appendGroup)
                groupRangesByKey[key] = start ..< Int32(groups.count)
            }
            let swiftTypeStart = Int32(groups.count)
            for target in swiftTypeTargets {
                guard case .swiftType(let descriptor) = target else { continue }
                let start = Int32(groups.count)
                appendGroup(target)
                groupRangesByKey[.swiftTypeDescriptor(descriptor)] = start ..< Int32(groups.count)
            }
            let swiftTypeNameStart = Int32(groups.count)
            swiftTypeNameTargets.forEach(appendGroup)
            nameBytes += classNames.reduce(0) { $0 + Self.heapByteCount(of: $1) }

            let dictionaryBucketByteCount = MemoryLayout<CodeReferenceTable.Key>.stride + MemoryLayout<Range<Int32>>.stride
            let approximateByteCount = entries.count * MemoryLayout<Entry>.stride
                + groups.count * MemoryLayout<Group>.stride
                + groupRangesByKey.capacity * dictionaryBucketByteCount
                + classNames.count * MemoryLayout<String>.stride
                + nameBytes
            return CodeReferenceIndex(
                imageIndex: imageIndex,
                approximateByteCount: approximateByteCount,
                codeStart: codeStart,
                entries: entries,
                groups: groups,
                groupRangesByKey: groupRangesByKey,
                swiftTypeGroupRange: swiftTypeStart ..< swiftTypeNameStart,
                swiftTypeNameGroupRange: swiftTypeNameStart ..< Int32(groups.count),
                classNames: classNames
            )
        }

        /// The heap a name holds beyond the string value itself: none for one
        /// short enough to be stored inline.
        private static func heapByteCount(of name: String) -> Int {
            let byteCount = name.utf8.count
            return byteCount > 15 ? byteCount + 32 : 0
        }

        private static func heapByteCount(of target: Target) -> Int {
            switch target {
            case .importedSymbol(let name), .messageSend(let name), .superMessageSend(let name), .objectiveCClass(let name, _):
                return heapByteCount(of: name)
            case .swiftTypeName(.accessorSymbol(let symbol)):
                return heapByteCount(of: symbol)
            case .function, .swiftType, .swiftTypeName(.mangledName):
                return 0
            }
        }
    }
}
