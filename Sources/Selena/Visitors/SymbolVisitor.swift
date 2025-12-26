//
//  SymbolVisitor.swift
//  SwiftMCPServer
//
//  Created by k_terada on 2025/10/03.
//

import SwiftSyntax

/// シンボル（Class, Struct, Function等）を抽出するVisitor
class SymbolVisitor: SyntaxVisitor {
    var symbols: [SwiftSyntaxAnalyzer.SymbolInfo] = []
    let converter: SourceLocationConverter

    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)
        symbols.append(SwiftSyntaxAnalyzer.SymbolInfo(
            name: node.name.text,
            kind: "Class",
            line: location.line
        ))
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)
        symbols.append(SwiftSyntaxAnalyzer.SymbolInfo(
            name: node.name.text,
            kind: "Struct",
            line: location.line
        ))
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)
        symbols.append(SwiftSyntaxAnalyzer.SymbolInfo(
            name: node.name.text,
            kind: "Enum",
            line: location.line
        ))
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)
        symbols.append(SwiftSyntaxAnalyzer.SymbolInfo(
            name: node.name.text,
            kind: "Protocol",
            line: location.line
        ))
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)
        symbols.append(SwiftSyntaxAnalyzer.SymbolInfo(
            name: node.name.text,
            kind: "Actor",
            line: location.line
        ))
        return .visitChildren
    }

    // Swift 5.9+: Macro declarations
    override func visit(_ node: MacroDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)
        symbols.append(SwiftSyntaxAnalyzer.SymbolInfo(
            name: node.name.text,
            kind: "Macro",
            line: location.line
        ))
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)
        symbols.append(SwiftSyntaxAnalyzer.SymbolInfo(
            name: node.name.text,
            kind: "TypeAlias",
            line: location.line
        ))
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)
        symbols.append(SwiftSyntaxAnalyzer.SymbolInfo(
            name: node.name.text,
            kind: "Function",
            line: location.line
        ))
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)
        for binding in node.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                symbols.append(SwiftSyntaxAnalyzer.SymbolInfo(
                    name: identifier.identifier.text,
                    kind: "Variable",
                    line: location.line
                ))
            }
        }
        return .visitChildren
    }
}
