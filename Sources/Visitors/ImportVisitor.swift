//
//  ImportVisitor.swift
//  SwiftMCPServer
//
//  Created by k_terada on 2025/10/03.
//

import SwiftSyntax

/// Import文を抽出するVisitor
class ImportVisitor: SyntaxVisitor {
    var imports: [SwiftSyntaxAnalyzer.ImportInfo] = []
    let converter: SourceLocationConverter

    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)

        // モジュール名を取得
        let moduleName = node.path.map { $0.name.text }.joined(separator: ".")

        // importの種類（typealias, struct, class, func等）
        var kind: String? = nil
        if let importKind = node.importKindSpecifier {
            kind = importKind.text
        }

        // 特定のシンボルをimportしている場合（未実装、将来的に対応）
        let symbols: [String] = []

        imports.append(SwiftSyntaxAnalyzer.ImportInfo(
            module: moduleName,
            kind: kind,
            symbols: symbols,
            line: location.line
        ))

        return .visitChildren
    }
}
