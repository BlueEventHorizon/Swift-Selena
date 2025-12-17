//
//  SwiftTestingVisitor.swift
//  SwiftMCPServer
//
//  Created on 2025/12/15.
//

import SwiftSyntax

/// Swift Testing (@Test, @Suite) を検出するVisitor
/// Swift 5.9+で導入された新しいテストフレームワーク対応
class SwiftTestingVisitor: SyntaxVisitor {
    var testSuites: [SwiftSyntaxAnalyzer.SwiftTestInfo] = []
    let converter: SourceLocationConverter
    let filePath: String

    // 現在処理中のSuite情報
    private var currentSuite: (name: String, kind: String, line: Int)?
    private var currentTests: [SwiftSyntaxAnalyzer.SwiftTestInfo.TestMethod] = []

    init(converter: SourceLocationConverter, filePath: String) {
        self.converter = converter
        self.filePath = filePath
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Struct

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        processTypeDecl(
            name: node.name.text,
            kind: "Struct",
            attributes: node.attributes,
            members: node.memberBlock.members,
            startLocation: node.startLocation(converter: converter)
        )
        return .skipChildren
    }

    // MARK: - Class

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        // XCTestCaseを継承しているクラスはXCTestVisitorに任せる
        let inheritsXCTestCase = node.inheritanceClause?.inheritedTypes.contains { inherited in
            inherited.type.trimmedDescription.contains("XCTestCase")
        } ?? false

        if !inheritsXCTestCase {
            processTypeDecl(
                name: node.name.text,
                kind: "Class",
                attributes: node.attributes,
                members: node.memberBlock.members,
                startLocation: node.startLocation(converter: converter)
            )
        }
        return .skipChildren
    }

    // MARK: - Enum

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        processTypeDecl(
            name: node.name.text,
            kind: "Enum",
            attributes: node.attributes,
            members: node.memberBlock.members,
            startLocation: node.startLocation(converter: converter)
        )
        return .skipChildren
    }

    // MARK: - Private Helpers

    private func processTypeDecl(
        name: String,
        kind: String,
        attributes: AttributeListSyntax,
        members: MemberBlockItemListSyntax,
        startLocation: SourceLocation
    ) {
        // @Suiteアトリビュートをチェック
        let hasSuiteAttribute = hasAttribute(named: "Suite", in: attributes)

        // メンバー内の@Testメソッドを検出
        var testMethods: [SwiftSyntaxAnalyzer.SwiftTestInfo.TestMethod] = []

        for member in members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                if hasAttribute(named: "Test", in: funcDecl.attributes) {
                    let funcLocation = funcDecl.startLocation(converter: converter)
                    let displayName = extractTestDisplayName(from: funcDecl.attributes) ?? funcDecl.name.text
                    testMethods.append(SwiftSyntaxAnalyzer.SwiftTestInfo.TestMethod(
                        name: funcDecl.name.text,
                        displayName: displayName,
                        line: funcLocation.line
                    ))
                }
            }
        }

        // @Suiteがあるか、@Testメソッドがある場合にテストスイートとして登録
        if hasSuiteAttribute || !testMethods.isEmpty {
            let suiteDisplayName = extractSuiteDisplayName(from: attributes) ?? name
            testSuites.append(SwiftSyntaxAnalyzer.SwiftTestInfo(
                suiteName: name,
                suiteDisplayName: suiteDisplayName,
                suiteKind: kind,
                filePath: filePath,
                line: startLocation.line,
                hasSuiteAttribute: hasSuiteAttribute,
                testMethods: testMethods
            ))
        }
    }

    private func hasAttribute(named attributeName: String, in attributes: AttributeListSyntax) -> Bool {
        for attribute in attributes {
            if case .attribute(let attr) = attribute {
                let attrName = attr.attributeName.trimmedDescription
                if attrName == attributeName {
                    return true
                }
            }
        }
        return false
    }

    /// @Suite("表示名") から表示名を抽出
    private func extractSuiteDisplayName(from attributes: AttributeListSyntax) -> String? {
        for attribute in attributes {
            if case .attribute(let attr) = attribute {
                if attr.attributeName.trimmedDescription == "Suite" {
                    return extractStringArgument(from: attr)
                }
            }
        }
        return nil
    }

    /// @Test("表示名") から表示名を抽出
    private func extractTestDisplayName(from attributes: AttributeListSyntax) -> String? {
        for attribute in attributes {
            if case .attribute(let attr) = attribute {
                if attr.attributeName.trimmedDescription == "Test" {
                    return extractStringArgument(from: attr)
                }
            }
        }
        return nil
    }

    /// アトリビュートの最初の文字列引数を抽出
    private func extractStringArgument(from attribute: AttributeSyntax) -> String? {
        guard let arguments = attribute.arguments else { return nil }

        if case .argumentList(let argList) = arguments {
            if let firstArg = argList.first {
                // StringLiteralExprSyntaxから文字列を抽出
                if let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self) {
                    // セグメントから文字列を取得
                    let content = stringLiteral.segments.map { segment -> String in
                        if case .stringSegment(let seg) = segment {
                            return seg.content.text
                        }
                        return ""
                    }.joined()
                    return content.isEmpty ? nil : content
                }
            }
        }
        return nil
    }
}
