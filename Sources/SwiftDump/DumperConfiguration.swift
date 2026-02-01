import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import MemberwiseInit
import Demangling
import SwiftInspection

// MARK: - Identifiable Closure

/// A wrapper that pairs a closure with a stable identity for equatable comparison.
public struct IdentifiableClosure<Input, Output>: Sendable {
    public let id: UUID
    public let closure: @Sendable (Input) -> Output

    public init(id: UUID = UUID(), _ closure: @escaping @Sendable (Input) -> Output) {
        self.id = id
        self.closure = closure
    }

    public func callAsFunction(_ input: Input) -> Output {
        closure(input)
    }
}

extension IdentifiableClosure: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Transformer Closure Type Aliases

public typealias FieldOffsetTransformer = IdentifiableClosure<(startOffset: Int, endOffset: Int?), SemanticString>
public typealias TypeLayoutTransformer = IdentifiableClosure<TypeLayout, SemanticString>
public typealias EnumLayoutTransformer = IdentifiableClosure<EnumLayoutCalculator.LayoutResult, SemanticString>
public typealias EnumLayoutCaseTransformer = IdentifiableClosure<(caseProjection: EnumLayoutCalculator.EnumCaseProjection, indentation: Int), SemanticString>

// MARK: - Dumper Configuration

@MemberwiseInit(.public)
public struct DumperConfiguration: Sendable {
    public var demangleResolver: DemangleResolver
    public var indentation: Int = 1
    public var displayParentName: Bool = true
    public var printFieldOffset: Bool = false
    public var printTypeLayout: Bool = false
    public var printEnumLayout: Bool = false
    public var fieldOffsetTransformer: FieldOffsetTransformer? = nil
    public var typeLayoutTransformer: TypeLayoutTransformer? = nil
    public var enumLayoutTransformer: EnumLayoutTransformer? = nil
    public var enumLayoutCaseTransformer: EnumLayoutCaseTransformer? = nil

    public static func demangleOptions(_ demangleOptions: DemangleOptions) -> Self {
        .init(demangleResolver: .options(demangleOptions))
    }
}

extension DumperConfiguration {
    package var indentString: Indent {
        .init(level: indentation)
    }

    /// Builds a field offset comment line for the given start and end offsets.
    ///
    /// The returned ``SemanticString`` includes indentation and a trailing line break.
    @SemanticStringBuilder
    package func fieldOffsetComment(startOffset: Int, endOffset: Int?) -> SemanticString {
        indentString
        if let fieldOffsetTransformer {
            fieldOffsetTransformer((startOffset, endOffset))
        } else {
            Comment("Field Offset: 0x\(String(startOffset, radix: 16))")
        }
        BreakLine()
    }

    /// Builds an enum layout per-case comment block for the given case projection.
    @SemanticStringBuilder
    package func enumLayoutCaseComment(caseProjection: EnumLayoutCalculator.EnumCaseProjection) -> SemanticString {
        if let enumLayoutCaseTransformer {
            enumLayoutCaseTransformer((caseProjection: caseProjection, indentation: indentation))
        } else {
            AtomicComponent(string: caseProjection.description(indent: indentation, prefix: "//"), type: .comment)
        }
    }

    /// Builds an enum layout strategy comment line for the given layout result.
    ///
    /// The returned ``SemanticString`` includes indentation and a trailing line break.
    @SemanticStringBuilder
    package func enumLayoutComment(layoutResult: EnumLayoutCalculator.LayoutResult) -> SemanticString {
        indentString
        if let enumLayoutTransformer {
            enumLayoutTransformer(layoutResult)
        } else {
            InlineComment(layoutResult.strategyDescription)
        }
        BreakLine()
    }
}
