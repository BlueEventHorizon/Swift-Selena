//
//  TypeConformanceVisitor.swift
//  SwiftMCPServer
//
//  Created by k_terada on 2025/10/03.
//

import SwiftSyntax

/// Protocol準拠と継承関係を抽出するVisitor
class TypeConformanceVisitor: SyntaxVisitor {
    var typeConformances: [SwiftSyntaxAnalyzer.TypeConformanceInfo] = []
    let converter: SourceLocationConverter

    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)
        let (protocols, superclass) = extractInheritance(from: node.inheritanceClause)

        typeConformances.append(SwiftSyntaxAnalyzer.TypeConformanceInfo(
            typeName: node.name.text,
            typeKind: "Class",
            protocols: protocols,
            superclass: superclass,
            line: location.line
        ))

        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)
        let (protocols, _) = extractInheritance(from: node.inheritanceClause)

        typeConformances.append(SwiftSyntaxAnalyzer.TypeConformanceInfo(
            typeName: node.name.text,
            typeKind: "Struct",
            protocols: protocols,
            superclass: nil,
            line: location.line
        ))

        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)
        let (protocols, _) = extractInheritance(from: node.inheritanceClause)

        typeConformances.append(SwiftSyntaxAnalyzer.TypeConformanceInfo(
            typeName: node.name.text,
            typeKind: "Enum",
            protocols: protocols,
            superclass: nil,
            line: location.line
        ))

        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)
        let (protocols, superclass) = extractInheritance(from: node.inheritanceClause)

        typeConformances.append(SwiftSyntaxAnalyzer.TypeConformanceInfo(
            typeName: node.name.text,
            typeKind: "Actor",
            protocols: protocols,
            superclass: superclass,
            line: location.line
        ))

        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)

        // Protocolが継承している他のProtocol
        var protocols: [String] = []
        if let inheritanceClause = node.inheritanceClause {
            protocols = inheritanceClause.inheritedTypes.map { $0.type.trimmedDescription }
        }

        typeConformances.append(SwiftSyntaxAnalyzer.TypeConformanceInfo(
            typeName: node.name.text,
            typeKind: "Protocol",
            protocols: protocols,
            superclass: nil,
            line: location.line
        ))

        return .visitChildren
    }

    private func extractInheritance(from clause: InheritanceClauseSyntax?) -> (protocols: [String], superclass: String?) {
        guard let clause = clause else {
            return ([], nil)
        }

        var protocols: [String] = []
        var superclass: String? = nil

        // 最初の要素がクラス名（大文字始まり）の場合はスーパークラスの可能性
        let inheritedTypes = clause.inheritedTypes.map { $0.type.trimmedDescription }

        for (index, type) in inheritedTypes.enumerated() {
            // 最初の要素で大文字始まりの場合、スーパークラスの可能性
            // ただし、プロトコルも大文字始まりなので、正確な判別は難しい
            // ここでは全てプロトコルとして扱い、必要に応じてスーパークラスを分離
            if index == 0 && type.first?.isUppercase == true {
                // 一般的なプロトコル名でなければスーパークラスとして扱う
                let commonProtocols = ["View", "ObservableObject", "Identifiable", "Codable",
                                     "Equatable", "Hashable", "Comparable", "CustomStringConvertible"]
                if !commonProtocols.contains(type) && !type.contains("Delegate") && !type.contains("Protocol") {
                    superclass = type
                    continue
                }
            }
            protocols.append(type)
        }

        return (protocols, superclass)
    }
}
