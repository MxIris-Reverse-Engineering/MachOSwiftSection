import Foundation
import MachOKit
import ARM64InstructionDecoding

/// Where the references only the Swift layer recognizes go.
protocol SwiftCodeReferenceRecording: CodeReferenceRecording {
    func recordSwiftType(descriptor: CodeLocation, at site: ScanSite)
    func recordSwiftTypeName(_ name: SwiftTypeName, at site: ScanSite)
}

/// The Swift runtime's functions a scan recognizes by name, collected from
/// the runtime libraries' symbols when an analyzer is built.
struct SwiftRuntimeFunctions: Sendable {
    /// The runtime's entry points that instantiate a type from its mangled
    /// name, and the register each takes the name in: `x0`, or `x1` for the
    /// `…InMetadataState` forms, whose first argument is the state.
    private(set) var typeByMangledNameEntries: [CodeLocation: Int] = [:]
    /// `swift_getInitializedObjCClass`, which returns the class it is handed
    /// in `x0`.
    private(set) var classReturningFunctions = Set<CodeLocation>()

    /// Notes the runtime library symbol `name` at `location` when it is one
    /// of the Swift runtime's.
    mutating func consider(_ name: UnsafePointer<CChar>, at location: CodeLocation) {
        if Self.returnsItsClassArgument(name) {
            classReturningFunctions.insert(location)
        } else if strncmp(name, "_swift_getTypeByMangledNameIn", 29) == 0 {
            typeByMangledNameEntries[location] = strstr(name, "InMetadataState") == nil ? 0 : 1
        }
    }

    static func returnsItsClassArgument(_ name: UnsafePointer<CChar>) -> Bool {
        strcmp(name, "_swift_getInitializedObjCClass") == 0
    }

    /// The libraries whose exported functions the layer recognizes.
    static func isRuntimeLibrary(_ path: String) -> Bool {
        path.hasSuffix("/libswiftCore.dylib") || path.hasSuffix("/libswift_Concurrency.dylib")
    }
}

/// The Swift layer of the cross-reference analysis: Swift types reached
/// through their metadata accessors, their metadata, and the mangled names
/// code instantiates. Evolution proposals `cross-reference-analysis`,
/// `offline-cross-references-and-symbolication`.
///
/// Keeps every image's Swift type index it was asked for, like the core
/// keeps function tables.
final class SwiftCodeReferenceRecognizer: @unchecked Sendable {
    let images: CodeImageSet
    let runtimeFunctions: SwiftRuntimeFunctions
    private let lock = NSLock()
    private var typeIndexes: [Int: SwiftTypeIndex] = [:]

    init(images: CodeImageSet, runtimeFunctions: SwiftRuntimeFunctions) {
        self.images = images
        self.runtimeFunctions = runtimeFunctions
    }

    /// A session for one scan of the image `table` covers. `findsTypeReferences`:
    /// whether the scan looks for type references at all.
    func makeSession(table: ImageFunctionTable, recording: any SwiftCodeReferenceRecording, findsTypeReferences: Bool) -> SwiftCodeReferenceRecognitionSession {
        SwiftCodeReferenceRecognitionSession(recognizer: self, table: table, recording: recording, findsTypeReferences: findsTypeReferences)
    }

    /// The image's Swift type index, built on first use and then kept.
    func typeIndex(ofImageAt imageIndex: Int) -> SwiftTypeIndex {
        lock.lock()
        if let index = typeIndexes[imageIndex] {
            lock.unlock()
            return index
        }
        lock.unlock()
        let index = SwiftTypeIndex(image: images.images[imageIndex], imageIndex: imageIndex, memory: images.memory)
        lock.lock()
        defer { lock.unlock() }
        if let stored = typeIndexes[imageIndex] { return stored }
        typeIndexes[imageIndex] = index
        return index
    }

    func existingTypeIndex(ofImageAt imageIndex: Int) -> SwiftTypeIndex? {
        lock.lock()
        defer { lock.unlock() }
        return typeIndexes[imageIndex]
    }

    /// Drops the type indexes of every image but `keptImageIndices`, and
    /// returns them so that the caller frees them outside any lock.
    func releaseTypeIndexes(exceptForImagesAt keptImageIndices: Set<Int>) -> [Int: SwiftTypeIndex] {
        lock.lock()
        defer { lock.unlock() }
        let released = typeIndexes
        typeIndexes = typeIndexes.filter { keptImageIndices.contains($0.key) }
        return released
    }
}

/// One scan of one image by the Swift layer, on one thread.
final class SwiftCodeReferenceRecognitionSession: CodeReferenceRecognitionSession {
    private let recognizer: SwiftCodeReferenceRecognizer
    private let images: CodeImageSet
    private let table: ImageFunctionTable
    private let recording: any SwiftCodeReferenceRecording
    private let findsTypeReferences: Bool
    private let resolver: CallTargetResolver

    /// What calling a function stands for besides the call.
    private enum TypeFunction {
        /// A type's metadata accessor: the type's descriptor.
        case accessor(descriptor: CodeLocation)
        /// A metadata accessor no descriptor stands for: its symbol, without
        /// the leading underscore.
        case accessorSymbol(String)
        /// `__swift_instantiateConcreteTypeFromMangledName…`: the V2 helpers
        /// take the name's `{ offset, length }` record in `x1`, the older ones
        /// a cache variable in `x0`.
        case instantiationHelper(takesRecord: Bool)
        /// `swift_getTypeByMangledName…`: the name in this register.
        case runtimeEntry(nameRegister: Int)
    }

    /// What role `n` stands for: `rolePlans[n - 1]`.
    private struct RolePlan {
        var typeFunction: TypeFunction?
        /// `swift_getInitializedObjCClass`: `x0` survives the call.
        var returnsItsClassArgument = false
    }

    @exclusivity(unchecked)
    private var rolePlans: [RolePlan] = []
    @exclusivity(unchecked)
    private var typeIndexes: [Int: SwiftTypeIndex] = [:]
    @exclusivity(unchecked)
    private var addressDescriptors: [UInt: CodeLocation?] = [:]
    @exclusivity(unchecked)
    private var slotDescriptors: [UInt: CodeLocation?] = [:]

    init(recognizer: SwiftCodeReferenceRecognizer, table: ImageFunctionTable, recording: any SwiftCodeReferenceRecording, findsTypeReferences: Bool) {
        self.recognizer = recognizer
        self.images = recognizer.images
        self.table = table
        self.recording = recording
        self.findsTypeReferences = findsTypeReferences
        self.resolver = CallTargetResolver(images: recognizer.images, table: table)
    }

    var referenceSlotRanges: [Range<UInt64>] { [] }
    var watchedSlotRanges: [Range<UInt64>] { [] }
    var looksForAddressReferences: Bool { findsTypeReferences }

    func enterFunction(at functionIndex: Int, registers: RegisterFile) {}

    func claimCallTarget(at target: UInt64) -> CallTargetClaim? { nil }

    func noteWatchedSlotLoad(from slot: UInt64, at site: ScanSite) {}

    // MARK: - Calls

    func role(of target: ResolvedCallTarget) -> CalleeRole? {
        var plan = RolePlan()
        switch target {
        case .function(let location):
            plan.returnsItsClassArgument = recognizer.runtimeFunctions.classReturningFunctions.contains(location)
            if findsTypeReferences { plan.typeFunction = typeFunction(at: location) }
        case .importedSymbol(let name):
            plan.returnsItsClassArgument = SwiftRuntimeFunctions.returnsItsClassArgument(name)
            if findsTypeReferences, let accessorSymbol = Self.accessorSymbol(name) { plan.typeFunction = .accessorSymbol(accessorSymbol) }
        case .registerSettingTrampoline, .unrecognized:
            return nil
        }
        guard plan.typeFunction != nil || plan.returnsItsClassArgument else { return nil }
        rolePlans.append(plan)
        return CalleeRole(code: UInt32(rolePlans.count), mayStandIn: false, notesCallMade: true)
    }

    func recordCallStandIn(_ call: ScannedCall, registers: RegisterFile) -> Bool { false }

    /// The type reference a call makes besides the call itself: to the type
    /// whose metadata accessor it calls, or to the types the mangled name it
    /// instantiates names.
    func noteCallMade(_ call: ScannedCall, registers: RegisterFile) -> UInt32 {
        let plan = rolePlans[Int(call.role) - 1]
        if let typeFunction = plan.typeFunction {
            let site = call.site.referencing(as: .reference)
            switch typeFunction {
            case .accessor(let descriptor):
                recording.recordSwiftType(descriptor: descriptor, at: site)
            case .accessorSymbol(let symbol):
                recording.recordSwiftTypeName(.accessorSymbol(symbol), at: site)
            case .instantiationHelper(let takesRecord):
                if let name = takesRecord ? mangledNameInRecord(inRegister: 1, registers) : mangledNameInCacheVariable(inRegister: 0, registers) {
                    recording.recordSwiftTypeName(name, at: site)
                }
            case .runtimeEntry(let nameRegister):
                if let name = mangledName(inRegister: nameRegister, registers) {
                    recording.recordSwiftTypeName(name, at: site)
                }
            }
        }
        return plan.returnsItsClassArgument ? 1 : 0
    }

    /// What a function stands for besides a call: a type's metadata
    /// accessor — by its descriptor, or by its symbol when no descriptor
    /// stands for it — a mangled-name instantiation helper, or one of the
    /// runtime's entry points that instantiate a type from its mangled name.
    private func typeFunction(at location: CodeLocation) -> TypeFunction? {
        if let nameRegister = recognizer.runtimeFunctions.typeByMangledNameEntries[location] { return .runtimeEntry(nameRegister: nameRegister) }
        if let descriptor = typeIndex(ofImageAt: location.imageIndex).descriptorLocation(ofAccessorAt: images.runtimeAddress(of: location)) {
            return .accessor(descriptor: descriptor)
        }
        // Accessors of generic instances and mangled-name helpers are emitted
        // into each image that uses them.
        guard location.imageIndex == table.imageIndex,
              let functionIndex = table.functionIndex(containing: location.address),
              table.starts[functionIndex] == location.address
        else { return nil }
        if let name = table.primaryName(ofFunctionAt: functionIndex) {
            if let accessorSymbol = Self.accessorSymbol(name) { return .accessorSymbol(accessorSymbol) }
            guard strstr(name, "instantiateConcreteTypeFromMangledName") != nil else { return nil }
            let length = strlen(name)
            return .instantiationHelper(takesRecord: length > 2 && name[length - 2] == 0x56 && name[length - 1] == 0x32)
        }
        return instantiationHelperByShape(ofFunctionAt: functionIndex)
    }

    /// A mangled-name helper without a symbol, told by what it does: a short
    /// function that calls the runtime's `swift_getTypeByMangledName…`. The V2
    /// helpers read their record through `x1` (`ldr x9, [x1]`); the older
    /// ones take nothing in `x1`.
    private func instantiationHelperByShape(ofFunctionAt functionIndex: Int) -> TypeFunction? {
        let start = table.starts[functionIndex]
        let end = table.end(ofFunctionAt: functionIndex)
        guard end > start, end - start <= 0x90, let words = table.instructionPointer(at: start, count: Int((end - start) / 4)) else { return nil }
        var readsRecord = false
        var callsRuntime = false
        for instructionIndex in 0 ..< Int((end - start) / 4) {
            let instructionAddress = start &+ UInt64(instructionIndex * 4)
            let word = UInt32(littleEndian: words[instructionIndex])
            if let load = ARM64InstructionWord.load(word), load.base == 1, load.displacement == 0 {
                readsRecord = true
            } else if let callee = ARM64InstructionWord.callTarget(word, at: instructionAddress) ?? ARM64InstructionWord.branchTarget(word, at: instructionAddress),
                      callee < start || callee >= end,
                      case .function(let calleeLocation) = resolver.resolve(callee),
                      recognizer.runtimeFunctions.typeByMangledNameEntries[calleeLocation] != nil {
                callsRuntime = true
            }
        }
        return callsRuntime ? .instantiationHelper(takesRecord: readsRecord) : nil
    }

    /// `_$s…Ma` without its leading underscore, for a metadata accessor's
    /// symbol.
    private static func accessorSymbol(_ name: UnsafePointer<CChar>) -> String? {
        guard name[0] == 0x5F, name[1] == 0x24, name[2] == 0x73 else { return nil }
        let length = strlen(name)
        guard length > 5, name[length - 2] == 0x4D, name[length - 1] == 0x61 else { return nil }
        return String(cString: name + 1)
    }

    // MARK: - Type references

    func recordAddressReference(toRuntimeAddress address: UInt, isCode: Bool, at site: ScanSite) -> Bool {
        guard findsTypeReferences else { return false }
        let descriptor: CodeLocation?
        if let known = addressDescriptors[address] {
            descriptor = known
        } else {
            descriptor = isCode ? accessorDescriptor(atRuntimeAddress: address) : valueMetadataDescriptor(atRuntimeAddress: address)
            addressDescriptors[address] = descriptor
        }
        guard let descriptor else { return false }
        recording.recordSwiftType(descriptor: descriptor, at: site)
        return true
    }

    func recordSlotReference(holding value: UInt, at site: ScanSite) -> Bool {
        guard findsTypeReferences else { return false }
        let descriptor: CodeLocation?
        if let known = slotDescriptors[value] {
            descriptor = known
        } else {
            descriptor = valueMetadataDescriptor(atRuntimeAddress: value) ?? accessorDescriptor(atRuntimeAddress: value)
            slotDescriptors[value] = descriptor
        }
        guard let descriptor else { return false }
        recording.recordSwiftType(descriptor: descriptor, at: site)
        return true
    }

    /// The descriptor of the type whose metadata accessor starts at the
    /// runtime `address`.
    private func accessorDescriptor(atRuntimeAddress address: UInt) -> CodeLocation? {
        guard let imageIndex = images.imageIndex(containingRuntimeAddress: address) else { return nil }
        return typeIndex(ofImageAt: imageIndex).descriptorLocation(ofAccessorAt: address)
    }

    /// The descriptor of the type whose metadata lies at the runtime
    /// `address`: a struct, an enum, an optional or an imported type, whose
    /// metadata holds its kind first and its descriptor next. A Swift class's
    /// metadata is its Objective-C class object, which the Objective-C layer
    /// recognizes first.
    private func valueMetadataDescriptor(atRuntimeAddress address: UInt) -> CodeLocation? {
        guard address != 0, images.isMapped(runtimeAddress: address, length: 16), let kind = images.memory.load(UInt64.self, at: address) else { return nil }
        // MetadataKind: struct 0x200, enum 0x201, optional 0x202, foreign
        // class 0x203, foreign reference type 0x204.
        guard kind >= 0x200, kind <= 0x204, let descriptor = images.memory.pointer(at: address &+ 8) else { return nil }
        guard let imageIndex = images.imageIndex(containingRuntimeAddress: descriptor) else { return nil }
        let index = typeIndex(ofImageAt: imageIndex)
        return index.describesType(descriptorAt: descriptor) ? index.location(ofRuntimeAddress: descriptor) : nil
    }

    /// The type indexes this scan asked for, kept here so that a lookup does
    /// not contend for the recognizer's lock.
    private func typeIndex(ofImageAt imageIndex: Int) -> SwiftTypeIndex {
        if let index = typeIndexes[imageIndex] { return index }
        let index = recognizer.typeIndex(ofImageAt: imageIndex)
        typeIndexes[imageIndex] = index
        return index
    }

    // MARK: - Mangled names

    /// The longest mangled name read; a longer one is taken for something
    /// else.
    private static let maximumMangledNameLength = 4096

    /// `__swift_instantiateConcreteTypeFromMangledNameV2`'s second argument:
    /// `{ int32 offset from the record to the name, int32 length }`.
    private func mangledNameInRecord(inRegister register: Int, _ registers: RegisterFile) -> SwiftTypeName? {
        guard let record = registers.builtAddress(of: register) else { return nil }
        let runtimeRecord = table.runtimeAddress(ofUnslid: record)
        guard runtimeRecord != 0, images.isMapped(runtimeAddress: runtimeRecord, length: 8),
              let offset = images.memory.load(Int32.self, at: runtimeRecord),
              let storedLength = images.memory.load(Int32.self, at: runtimeRecord &+ 4)
        else { return nil }
        return mangledName(at: ARM64InstructionWord.adding(Int64(offset), to: record), length: Int(storedLength))
    }

    /// The first argument of the older helper: a cache variable that holds
    /// `{ int32 offset from the variable to the name, int32 negated length }`
    /// until the type is instantiated, and its metadata afterwards — then the
    /// name is gone, and nothing is reported.
    private func mangledNameInCacheVariable(inRegister register: Int, _ registers: RegisterFile) -> SwiftTypeName? {
        guard let cache = registers.builtAddress(of: register) else { return nil }
        let runtimeCache = table.runtimeAddress(ofUnslid: cache)
        guard runtimeCache != 0, images.isMapped(runtimeAddress: runtimeCache, length: 8), let value = images.memory.load(Int64.self, at: runtimeCache) else { return nil }
        guard value < 0 else { return nil }
        return mangledName(at: ARM64InstructionWord.adding(Int64(Int32(truncatingIfNeeded: value)), to: cache), length: -Int(Int32(truncatingIfNeeded: value >> 32)))
    }

    /// The name a runtime entry point is handed, which runs to its
    /// terminator: a symbolic reference's payload is skipped, since it may
    /// hold zero bytes.
    private func mangledName(inRegister register: Int, _ registers: RegisterFile) -> SwiftTypeName? {
        guard let name = registers.builtAddress(of: register) else { return nil }
        let runtimeName = table.runtimeAddress(ofUnslid: name)
        let readableLength = Int(min(images.mappedLength(fromRuntimeAddress: runtimeName), UInt(Self.maximumMangledNameLength)))
        guard readableLength > 0, runtimeName != 0, let bytes = images.memory.typedPointer(to: UInt8.self, at: runtimeName, length: readableLength) else { return nil }
        var length = 0
        while length < readableLength {
            let byte = bytes[length]
            if byte == 0 { return mangledName(at: name, length: length) }
            length += byte >= 0x01 && byte <= 0x17 ? 5 : (byte >= 0x18 && byte <= 0x1F ? 9 : 1)
        }
        return nil
    }

    private func mangledName(at name: UInt64, length: Int) -> SwiftTypeName? {
        guard length > 0, length <= Self.maximumMangledNameLength,
              images.isMapped(runtimeAddress: table.runtimeAddress(ofUnslid: name), length: UInt(length))
        else { return nil }
        return .mangledName(location: CodeLocation(imageIndex: table.imageIndex, address: name), length: length)
    }
}
