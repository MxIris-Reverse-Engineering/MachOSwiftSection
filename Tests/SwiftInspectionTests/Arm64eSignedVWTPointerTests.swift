import Foundation
import Testing
@testable import SwiftInspection

// MARK: - Test Enum

private final class TaggedSlotBoxClass {
    var storedValue: Int = 0
}

/// A single-payload enum over a class reference: empty case `first` rides
/// extra inhabitant #0 (the null pointer, all-zero bytes) and `second` rides
/// pointer value 1 — patterns the projector must reproduce identically whether
/// it reached the value witness table through a clean or a tag-carrying slot.
private enum TaggedSlotSinglePayloadEnum {
    case wrapped(TaggedSlotBoxClass)
    case first
    case second
}

// MARK: - arm64e probe host support

/// Compiles and runs the on-the-fly arm64e programs backing the probe-layer
/// tests. Everything is memoized: one canary compile+run decides whether this
/// host can execute third-party arm64e processes at all (GitHub-hosted runners
/// cannot — the `-arm64e_preview_abi` boot-arg is unavailable there), and one
/// probe compile serves both the raw and the strip mode runs.
private enum Arm64eProbeHost {
    struct SpawnResult {
        let terminatedBySignal: Int32?
        let exitCode: Int32?
        let standardOutput: String
    }

    static let temporaryDirectoryURL: URL = {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Arm64eSignedVWTPointerProbe-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }()

    /// `nil` when the host can execute arm64e third-party processes; otherwise
    /// the reason the probe layer must skip.
    static let arm64eExecutionUnavailabilityReason: String? = {
        let canarySourceURL = temporaryDirectoryURL.appendingPathComponent("canary.c")
        let canaryBinaryURL = temporaryDirectoryURL.appendingPathComponent("canary")
        do {
            try "int main(void) { return 42; }\n".write(to: canarySourceURL, atomically: true, encoding: .utf8)
        } catch {
            return "cannot write canary source: \(error)"
        }
        guard let compileResult = try? spawn(
            executablePath: "/usr/bin/xcrun",
            arguments: ["clang", "-arch", "arm64e", "-o", canaryBinaryURL.path, canarySourceURL.path]
        ), compileResult.exitCode == 0 else {
            return "clang cannot produce an arm64e canary on this host"
        }
        guard let runResult = try? spawn(executablePath: canaryBinaryURL.path, arguments: []) else {
            return "the arm64e canary cannot be spawned (exec refused)"
        }
        guard runResult.exitCode == 42 else {
            return "the arm64e canary did not run to completion (signal \(runResult.terminatedBySignal.map(String.init) ?? "none"), exit \(runResult.exitCode.map(String.init) ?? "none")) — host lacks the -arm64e_preview_abi boot-arg"
        }
        return nil
    }()

    /// The compiled probe binary, or `nil` if compilation failed. The probe
    /// replicates the projector's slot handling on its own live enum metadata:
    /// `raw` mode dereferences the loaded slot value as-is (the pre-fix
    /// behavior — it must SIGSEGV in a genuine pointer-authenticating
    /// process), `strip` mode masks the tag bits first and then drives a full
    /// witness round trip through ptrauth-qualified stubs (the post-fix
    /// behavior — it must succeed).
    static let probeBinaryURL: URL? = {
        let headerURL = temporaryDirectoryURL.appendingPathComponent("probe.h")
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("probe.swift")
        let binaryURL = temporaryDirectoryURL.appendingPathComponent("probe")
        do {
            try probeBridgingHeaderSource.write(to: headerURL, atomically: true, encoding: .utf8)
            try probeProgramSource.write(to: sourceURL, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        guard let compileResult = try? spawn(
            executablePath: "/usr/bin/xcrun",
            arguments: [
                "swiftc",
                "-target", "arm64e-apple-macos14.0",
                "-import-objc-header", headerURL.path,
                sourceURL.path,
                "-o", binaryURL.path,
            ]
        ), compileResult.exitCode == 0 else {
            return nil
        }
        return binaryURL
    }()

    static func spawn(executablePath: String, arguments: [String]) throws -> SpawnResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let standardOutput = String(data: outputData, encoding: .utf8) ?? ""
        switch process.terminationReason {
        case .uncaughtSignal:
            return SpawnResult(terminatedBySignal: process.terminationStatus, exitCode: nil, standardOutput: standardOutput)
        default:
            return SpawnResult(terminatedBySignal: nil, exitCode: process.terminationStatus, standardOutput: standardOutput)
        }
    }

    /// Minimal copy of `MachOSwiftSectionC`'s `EnumValueWitnessTable` stubs:
    /// on arm64e every slot carries its `__ptrauth_swift_value_witness_function_pointer`
    /// qualifier (per-slot discriminators, address-diversified) so clang
    /// auth-verifies the pointer at the call, exactly like the library's stubs.
    private static let probeBridgingHeaderSource = """
    #include <stdint.h>
    #include <stddef.h>

    #if defined(__arm64e__)
    #include <ptrauth.h>
    #define PROBE_VWT_FP(key) __ptrauth_swift_value_witness_function_pointer(key)
    #else
    #define PROBE_VWT_FP(key)
    #endif

    typedef struct ProbeValueWitnessTable {
      void *(* PROBE_VWT_FP(0xda4a) initializeBufferWithCopyOfBuffer)(void *, void *, const void *);
      void (* PROBE_VWT_FP(0x04f8) destroy)(void *, const void *);
      void *(* PROBE_VWT_FP(0xe3ba) initializeWithCopy)(void *, void *, const void *);
      void *(* PROBE_VWT_FP(0x8751) assignWithCopy)(void *, void *, const void *);
      void *(* PROBE_VWT_FP(0x48d8) initializeWithTake)(void *, void *, const void *);
      void *(* PROBE_VWT_FP(0xefda) assignWithTake)(void *, void *, const void *);
      unsigned (* PROBE_VWT_FP(0x60f0) getEnumTagSinglePayload)(const void *, unsigned, const void *);
      void (* PROBE_VWT_FP(0xa0d1) storeEnumTagSinglePayload)(void *, unsigned, unsigned, const void *);
      size_t size;
      size_t stride;
      unsigned flags;
      unsigned extraInhabitantCount;
    } ProbeValueWitnessTable;

    typedef struct ProbeEnumValueWitnessTable {
      ProbeValueWitnessTable base;
      int (* PROBE_VWT_FP(0xa3b5) getEnumTag)(const void *, const void *);
      void (* PROBE_VWT_FP(0x041d) destructiveProjectEnumData)(void *, const void *);
      void (* PROBE_VWT_FP(0xb2e4) destructiveInjectEnumTag)(void *, unsigned, const void *);
    } ProbeEnumValueWitnessTable;

    static inline unsigned probe_getEnumTag(const void *table, const void *value, const void *metadata) {
      const ProbeEnumValueWitnessTable *witnessTable = (const ProbeEnumValueWitnessTable *)table;
      return (unsigned)witnessTable->getEnumTag(value, metadata);
    }

    static inline void probe_destructiveInjectEnumTag(const void *table, void *value, unsigned caseTag, const void *metadata) {
      const ProbeEnumValueWitnessTable *witnessTable = (const ProbeEnumValueWitnessTable *)table;
      witnessTable->destructiveInjectEnumTag(value, caseTag, metadata);
    }
    """

    private static let probeProgramSource = """
    import Darwin

    final class ProbeBoxClass {
        var storedValue: Int = 0
    }

    enum ProbeSinglePayloadEnum {
        case wrapped(ProbeBoxClass)
        case first
        case second
    }

    func flushedPrint(_ line: String) {
        print(line)
        fflush(stdout)
    }

    let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "strip"
    let metadataPointer = unsafeBitCast(ProbeSinglePayloadEnum.self, to: UnsafeRawPointer.self)
    let rawSlotValue = metadataPointer.load(fromByteOffset: -8, as: UInt64.self)
    let virtualAddressMask: UInt64 = 0x0000_7FFF_FFFF_FFFF
    flushedPrint("slotCarriesTagBits=\\((rawSlotValue & ~virtualAddressMask) != 0 ? 1 : 0)")

    let tableAddress = mode == "raw" ? rawSlotValue : rawSlotValue & virtualAddressMask
    guard let tablePointer = UnsafeRawPointer(bitPattern: UInt(tableAddress)) else {
        flushedPrint("tablePointerConstructionFailed")
        exit(3)
    }
    // 8 function-pointer slots (64 bytes), then size / stride / flags /
    // extraInhabitantCount. In `raw` mode this load is the pre-fix crash.
    let size = tablePointer.load(fromByteOffset: 64, as: UInt.self)
    let stride = tablePointer.load(fromByteOffset: 72, as: UInt.self)
    flushedPrint("size=\\(size) stride=\\(stride)")

    // Full witness round trip through the ptrauth-qualified stubs: inject the
    // first empty case (tag 1, extra inhabitant #0 = the null pointer) into a
    // zeroed buffer and read the tag back.
    let valueBuffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
    defer { valueBuffer.deallocate() }
    valueBuffer.initializeMemory(as: UInt8.self, repeating: 0, count: Int(size))
    probe_destructiveInjectEnumTag(tablePointer, valueBuffer, 1, metadataPointer)
    let readBackTag = probe_getEnumTag(tablePointer, valueBuffer, metadataPointer)
    flushedPrint("witnessRoundTripTag=\\(readBackTag)")
    exit(size == 8 && stride == 8 && readBackTag == 1 ? 0 : 4)
    """
}

// MARK: - Tests

@Suite("Arm64eSignedVWTPointer", .enabled(if: MemoryLayout<UnsafeRawPointer>.size == 8))
struct Arm64eSignedVWTPointerTests {
    /// The tag bits of the crash-report pointer `0x00418001010521e8`: every
    /// bit above the 47-bit VA mask. ORed onto a valid table address they
    /// yield a pointer that faults when dereferenced raw (bits 54/48/47 are
    /// outside the user VA on arm64 macOS and non-canonical on x86_64;
    /// top-byte-ignore cannot hide them) and that recovers the original
    /// address exactly under `stripPointerTags`' VA mask.
    private static let pointerAuthenticationTagBits: UInt64 = 0x0041_8000_0000_0000

    /// The behavioral wiring lock, runnable on every host including CI: a
    /// value-witness-table slot carrying PAC-style tag bits must be stripped
    /// before the projector dereferences it. Pre-fix this test crashed the
    /// process (SIGSEGV loading the table through the tagged pointer — the
    /// same fault the arm64e crash report shows); post-fix the projection
    /// through the tagged slot matches the one from the untouched metadata.
    @Test("A tag-carrying VWT slot is stripped before any dereference")
    func taggedTableSlotIsStrippedBeforeUse() throws {
        let realMetadataPointer = unsafeBitCast(TaggedSlotSinglePayloadEnum.self, to: UnsafeRawPointer.self)
        let realSlotValue = realMetadataPointer.load(
            fromByteOffset: -MemoryLayout<UnsafeRawPointer>.size,
            as: UInt64.self
        )
        #expect(realSlotValue & Self.pointerAuthenticationTagBits == 0, "the test premise needs a clean slot to tag")

        // A fake full metadata: [tagged VWT slot][kind][descriptor], with the
        // metadata pointer aimed one word past the slot, exactly like the real
        // `TargetFullMetadata` header the projector reads.
        let fakeFullMetadata = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<UInt64>.size * 3,
            alignment: MemoryLayout<UInt64>.alignment
        )
        defer { fakeFullMetadata.deallocate() }
        fakeFullMetadata.storeBytes(of: realSlotValue | Self.pointerAuthenticationTagBits, as: UInt64.self)
        UnsafeMutableRawPointer(fakeFullMetadata + MemoryLayout<UInt64>.size)
            .copyMemory(from: realMetadataPointer, byteCount: MemoryLayout<UInt64>.size * 2)
        let taggedSlotMetadataPointer = UnsafeRawPointer(fakeFullMetadata + MemoryLayout<UInt64>.size)

        let projectedThroughTaggedSlot = try #require(
            RuntimeEnumCaseProjector.projectCasePatterns(
                enumMetadataPointer: taggedSlotMetadataPointer,
                payloadCaseCount: 1,
                caseCount: 3
            )
        )
        let projectedThroughCleanSlot = try #require(
            RuntimeEnumCaseProjector.projectCasePatterns(
                enumMetadataPointer: realMetadataPointer,
                payloadCaseCount: 1,
                caseCount: 3
            )
        )
        try #require(projectedThroughTaggedSlot.count == projectedThroughCleanSlot.count)
        for (taggedSlotPattern, cleanSlotPattern) in zip(projectedThroughTaggedSlot, projectedThroughCleanSlot) {
            #expect(taggedSlotPattern.caseIndex == cleanSlotPattern.caseIndex)
            #expect(taggedSlotPattern.fixedBytes == cleanSlotPattern.fixedBytes)
        }
        #expect(projectedThroughTaggedSlot[2].fixedBytes[0] == 1, "case `second` rides extra inhabitant #1 (pointer value 1)")
    }

    /// Probe layer, gated on a host that can execute arm64e third-party
    /// processes (skipped with a reason elsewhere, e.g. GitHub-hosted
    /// runners): in a genuinely pointer-authenticating process the VWT slot
    /// carries PAC bits and a raw dereference must fault. This is also the
    /// negative control proving the probe does NOT inherit `swift test`'s
    /// PAC-stripped environment — if the raw mode ever exits cleanly, the
    /// verification environment itself has become a placebo.
    @Test(
        "arm64e probe: a raw slot dereference faults in a genuine PAC process",
        .enabled(
            if: Arm64eProbeHost.arm64eExecutionUnavailabilityReason == nil,
            "host cannot execute arm64e third-party processes (GitHub-hosted runners lack the -arm64e_preview_abi boot-arg)"
        )
    )
    func probeRawSlotDereferenceFaults() throws {
        let probeBinaryURL = try #require(Arm64eProbeHost.probeBinaryURL, "probe compilation failed")
        let result = try Arm64eProbeHost.spawn(executablePath: probeBinaryURL.path, arguments: ["raw"])
        #expect(result.standardOutput.contains("slotCarriesTagBits=1"), "the live VWT slot must carry PAC bits in a real arm64e process; output: \(result.standardOutput)")
        // A shell reports this as exit 139 (128 + SIGSEGV).
        #expect(
            result.terminatedBySignal == SIGSEGV || result.terminatedBySignal == SIGBUS,
            "raw dereference must fault; a clean exit means PAC is not being enforced (placebo environment); got signal \(result.terminatedBySignal.map(String.init) ?? "none"), exit \(result.exitCode.map(String.init) ?? "none"), output: \(result.standardOutput)"
        )
    }

    /// Probe layer, same gate: stripping the slot's tag bits first recovers
    /// the real table — the dereference succeeds and a full witness round trip
    /// (inject the first empty case, read its tag back) works through the
    /// ptrauth-qualified stubs, proving the stubs' address-diversified
    /// discriminators are computed from the correct (stripped) slot addresses.
    @Test(
        "arm64e probe: strip-then-dereference succeeds including the witness round trip",
        .enabled(
            if: Arm64eProbeHost.arm64eExecutionUnavailabilityReason == nil,
            "host cannot execute arm64e third-party processes (GitHub-hosted runners lack the -arm64e_preview_abi boot-arg)"
        )
    )
    func probeStrippedSlotProjectionSucceeds() throws {
        let probeBinaryURL = try #require(Arm64eProbeHost.probeBinaryURL, "probe compilation failed")
        let result = try Arm64eProbeHost.spawn(executablePath: probeBinaryURL.path, arguments: ["strip"])
        #expect(result.exitCode == 0, "strip mode must run to completion; got signal \(result.terminatedBySignal.map(String.init) ?? "none"), exit \(result.exitCode.map(String.init) ?? "none"), output: \(result.standardOutput)")
        #expect(result.standardOutput.contains("slotCarriesTagBits=1"))
        #expect(result.standardOutput.contains("size=8 stride=8"))
        #expect(result.standardOutput.contains("witnessRoundTripTag=1"))
    }
}
