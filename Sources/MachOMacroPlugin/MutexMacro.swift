import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct MutexMacro: PeerMacro, AccessorMacro {
    
    // MARK: - PeerMacro
    
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Only process variable declarations
        guard let varDecl = declaration.as(VariableDeclSyntax.self) else {
            throw MutexMacroError.requiresVariable
        }
        
        // Check that it's a stored property
        guard let binding = varDecl.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
            throw MutexMacroError.invalidPropertyBinding
        }
        
        // Check if it already has accessors
        if binding.accessorBlock != nil {
            throw MutexMacroError.cannotHaveExistingAccessors
        }
        
        // Get the type
        guard let type = binding.typeAnnotation?.type else {
            throw MutexMacroError.requiresExplicitType
        }
        
        // Check if it's a weak property
        let isWeak = isWeakProperty(varDecl)
        
        // For weak properties, verify it's optional
        if isWeak && !isOptionalType(type) {
            throw MutexMacroError.weakRequiresOptional
        }
        
        // Get initial value
        let initialValue: ExprSyntax
        if let initializer = binding.initializer {
            initialValue = initializer.value
        } else if isWeak {
            initialValue = ExprSyntax("nil")
        } else {
            throw MutexMacroError.requiresInitialValue
        }
        
        // Generate the private Mutex property
        let mutexName = "_\(pattern.identifier.text)"
        let accessLevel = extractAccessLevel(from: varDecl)
        let mutexAccessLevel = "private"
        
        let mutexDecl: DeclSyntax
        
        if isWeak {
            // Extract base type from optional
            let baseType = extractBaseType(from: type)
            
            // Generate Mutex storage with WeakBox
            mutexDecl = """
            \(raw: mutexAccessLevel) let \(raw: mutexName) = Mutex(WeakBox<\(raw: baseType)>(\(initialValue)))
            """
        } else {
            // For regular properties
            mutexDecl = """
            \(raw: mutexAccessLevel) let \(raw: mutexName) = Mutex<\(type)>(\(initialValue))
            """
        }
        
        return [mutexDecl]
    }
    
    // MARK: - AccessorMacro
    
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        // Only process variable declarations
        guard let varDecl = declaration.as(VariableDeclSyntax.self) else {
            throw MutexMacroError.requiresVariable
        }
        
        // Check that it's a stored property
        guard let binding = varDecl.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
            throw MutexMacroError.invalidPropertyBinding
        }
        
        // Check if it already has accessors
        if binding.accessorBlock != nil {
            throw MutexMacroError.cannotHaveExistingAccessors
        }
        
        // Check if it's a weak property
        let isWeak = isWeakProperty(varDecl)
        let mutexName = "_\(pattern.identifier.text)"
        
        // Generate different accessors based on whether it's weak
        if isWeak {
            // For weak properties, access through WeakBox
            let getter: AccessorDeclSyntax = """
                get {
                    \(raw: mutexName).withLock { $0.value }
                }
                """
            
            let setter: AccessorDeclSyntax = """
                set {
                    \(raw: mutexName).withLock { $0.value = newValue }
                }
                """
            
            return [getter, setter]
        } else {
            // For regular properties
            let getter: AccessorDeclSyntax = """
                get {
                    \(raw: mutexName).withLock { $0 }
                }
                """
            
            let setter: AccessorDeclSyntax = """
                set {
                    \(raw: mutexName).withLock { $0 = newValue }
                }
                """
            
            return [getter, setter]
        }
    }
    
    // MARK: - Helper Methods
    
    private static func isWeakProperty(_ varDecl: VariableDeclSyntax) -> Bool {
        return varDecl.modifiers.contains { modifier in
            modifier.name.tokenKind == .keyword(.weak)
        }
    }
    
    private static func isOptionalType(_ type: TypeSyntax) -> Bool {
        if type.is(OptionalTypeSyntax.self) {
            return true
        }
        if type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return true
        }
        // Check for explicit Optional<T> syntax
        if let genericType = type.as(IdentifierTypeSyntax.self),
           genericType.name.text == "Optional" {
            return true
        }
        return false
    }
    
    private static func extractBaseType(from type: TypeSyntax) -> String {
        if let optionalType = type.as(OptionalTypeSyntax.self) {
            return optionalType.wrappedType.description.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let implicitlyUnwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return implicitlyUnwrapped.wrappedType.description.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Handle generic types like Optional<T>
        if let genericType = type.as(IdentifierTypeSyntax.self),
           genericType.name.text == "Optional",
           let genericArgs = genericType.genericArgumentClause?.arguments.first {
            return genericArgs.argument.description.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return type.description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func extractAccessLevel(from varDecl: VariableDeclSyntax) -> String {
        for modifier in varDecl.modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.public):
                return "public"
            case .keyword(.internal):
                return "internal"
            case .keyword(.fileprivate):
                return "fileprivate"
            case .keyword(.private):
                return "private"
            case .keyword(.open):
                return "open"
            case .keyword(.package):
                return "package"
            default:
                continue
            }
        }
        return "internal" // Default access level
    }
}

// MARK: - Error Types

private enum MutexMacroError: Error, CustomStringConvertible, DiagnosticMessage {
    case requiresVariable
    case requiresInitialValue
    case requiresExplicitType
    case invalidPropertyBinding
    case cannotHaveExistingAccessors
    case weakRequiresOptional
    
    var description: String {
        switch self {
        case .requiresVariable:
            return "@Mutex can only be applied to a variable declaration."
        case .requiresInitialValue:
            return "@Mutex requires the property to have an initial value (except for weak properties)."
        case .requiresExplicitType:
            return "@Mutex requires an explicit type annotation."
        case .invalidPropertyBinding:
            return "@Mutex requires a valid property binding."
        case .cannotHaveExistingAccessors:
            return "@Mutex cannot be applied to computed properties or properties with existing accessors."
        case .weakRequiresOptional:
            return "@Mutex on weak properties requires the type to be optional."
        }
    }
    
    var message: String { description }
    
    var diagnosticID: MessageID {
        MessageID(domain: "MutexMacro", id: "\(self)")
    }
    
    var severity: DiagnosticSeverity { .error }
}
