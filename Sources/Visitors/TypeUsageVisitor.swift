//
//  TypeUsageVisitor.swift
//  SwiftMCPServer
//
//  Created by k_terada on 2025/10/04.
//

import SwiftSyntax

/// 型の使用箇所を抽出するVisitor
class TypeUsageVisitor: SyntaxVisitor {
    var typeUsages: [SwiftSyntaxAnalyzer.TypeUsageInfo] = []
    let converter: SourceLocationConverter
    let filePath: String
    let targetTypeName: String

    init(converter: SourceLocationConverter, filePath: String, targetTypeName: String) {
        self.converter = converter
        self.filePath = filePath
        self.targetTypeName = targetTypeName
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)

        for binding in node.bindings {
            if let typeAnnotation = binding.typeAnnotation {
                let typeName = typeAnnotation.type.trimmedDescription

                // 型名をチェック（配列やOptionalも考慮）
                if typeName.contains(targetTypeName) {
                    if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                        typeUsages.append(SwiftSyntaxAnalyzer.TypeUsageInfo(
                            typeName: targetTypeName,
                            usageKind: "Variable",
                            context: identifier.identifier.text,
                            filePath: filePath,
                            line: location.line
                        ))
                    }
                }
            }
        }

        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)
        let functionName = node.name.text

        // 関数の戻り値型をチェック
        if let returnType = node.signature.returnClause?.type.trimmedDescription {
            if returnType.contains(targetTypeName) {
                typeUsages.append(SwiftSyntaxAnalyzer.TypeUsageInfo(
                    typeName: targetTypeName,
                    usageKind: "ReturnType",
                    context: "func \(functionName)",
                    filePath: filePath,
                    line: location.line
                ))
            }
        }

        // 関数のパラメータをチェック
        for param in node.signature.parameterClause.parameters {
            let paramTypeName = param.type.trimmedDescription
            if paramTypeName.contains(targetTypeName) {
                let paramName = param.secondName?.text ?? param.firstName.text
                typeUsages.append(SwiftSyntaxAnalyzer.TypeUsageInfo(
                    typeName: targetTypeName,
                    usageKind: "Parameter",
                    context: "func \(functionName) - param \(paramName)",
                    filePath: filePath,
                    line: location.line
                ))
            }
        }

        return .visitChildren
    }
}
