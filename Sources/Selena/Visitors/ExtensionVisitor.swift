//
//  ExtensionVisitor.swift
//  SwiftMCPServer
//
//  Created by k_terada on 2025/10/03.
//

import SwiftSyntax

/// Extension（拡張）を抽出するVisitor
class ExtensionVisitor: SyntaxVisitor {
    var extensions: [SwiftSyntaxAnalyzer.ExtensionInfo] = []
    let converter: SourceLocationConverter

    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)
        let extendedType = node.extendedType.trimmedDescription

        // プロトコル準拠を取得
        var protocols: [String] = []
        if let inheritanceClause = node.inheritanceClause {
            protocols = inheritanceClause.inheritedTypes.map { $0.type.trimmedDescription }
        }

        // Extension内のメンバーを取得
        var members: [SwiftSyntaxAnalyzer.ExtensionInfo.MemberInfo] = []
        for member in node.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let memberLocation = funcDecl.startLocation(converter: converter)
                members.append(SwiftSyntaxAnalyzer.ExtensionInfo.MemberInfo(
                    name: funcDecl.name.text,
                    kind: "Function",
                    line: memberLocation.line
                ))
            } else if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                let memberLocation = varDecl.startLocation(converter: converter)
                for binding in varDecl.bindings {
                    if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                        members.append(SwiftSyntaxAnalyzer.ExtensionInfo.MemberInfo(
                            name: identifier.identifier.text,
                            kind: "Variable",
                            line: memberLocation.line
                        ))
                    }
                }
            } else if let initDecl = member.decl.as(InitializerDeclSyntax.self) {
                let memberLocation = initDecl.startLocation(converter: converter)
                members.append(SwiftSyntaxAnalyzer.ExtensionInfo.MemberInfo(
                    name: "init",
                    kind: "Initializer",
                    line: memberLocation.line
                ))
            }
        }

        extensions.append(SwiftSyntaxAnalyzer.ExtensionInfo(
            extendedType: extendedType,
            protocols: protocols,
            line: location.line,
            members: members
        ))

        return .visitChildren
    }
}
