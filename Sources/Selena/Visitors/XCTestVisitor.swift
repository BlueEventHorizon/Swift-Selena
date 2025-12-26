//
//  XCTestVisitor.swift
//  SwiftMCPServer
//
//  Created by k_terada on 2025/10/03.
//

import SwiftSyntax

/// XCTestCaseクラスとテストメソッドを抽出するVisitor
class XCTestVisitor: SyntaxVisitor {
    var testClasses: [SwiftSyntaxAnalyzer.XCTestInfo] = []
    let converter: SourceLocationConverter
    let filePath: String

    init(converter: SourceLocationConverter, filePath: String) {
        self.converter = converter
        self.filePath = filePath
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        // XCTestCaseを継承しているクラスを検出
        let inheritsXCTestCase = node.inheritanceClause?.inheritedTypes.contains { inherited in
            inherited.type.trimmedDescription.contains("XCTestCase")
        } ?? false

        if inheritsXCTestCase {
            let location = node.startLocation(converter: converter)
            var testMethods: [SwiftSyntaxAnalyzer.XCTestInfo.TestMethod] = []

            // クラス内のテストメソッドを検出
            for member in node.memberBlock.members {
                if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                    let funcName = funcDecl.name.text
                    // "test"で始まるメソッドを検出
                    if funcName.hasPrefix("test") && !funcName.hasPrefix("testPerformance") {
                        let funcLocation = funcDecl.startLocation(converter: converter)
                        testMethods.append(SwiftSyntaxAnalyzer.XCTestInfo.TestMethod(
                            name: funcName,
                            line: funcLocation.line
                        ))
                    }
                }
            }

            testClasses.append(SwiftSyntaxAnalyzer.XCTestInfo(
                className: node.name.text,
                filePath: filePath,
                line: location.line,
                testMethods: testMethods
            ))
        }

        return .visitChildren
    }
}
