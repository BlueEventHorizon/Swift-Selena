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

    // MARK: - Protocol/Class判定用の定数

    /// 既知のプロトコル（Apple SDK + 標準ライブラリ）
    private static let knownProtocols: Set<String> = [
        // SwiftUI
        "View", "ObservableObject", "Observable", "PreviewProvider", "App", "Scene",
        "ViewModifier", "ButtonStyle", "ToggleStyle", "PickerStyle", "ListStyle",
        "ShapeStyle", "Shape", "InsettableShape", "Animatable", "VectorArithmetic",
        "EnvironmentKey", "PreferenceKey", "DynamicProperty",
        // Concurrency (Swift 5.5+)
        "Sendable", "Actor", "GlobalActor",
        // Standard Library - Core
        "Identifiable", "Codable", "Encodable", "Decodable",
        "Equatable", "Hashable", "Comparable",
        "CustomStringConvertible", "CustomDebugStringConvertible",
        "LosslessStringConvertible", "TextOutputStreamable",
        "Error", "LocalizedError", "RecoverableError", "CustomNSError",
        "RawRepresentable", "CaseIterable",
        "Strideable", "AdditiveArithmetic", "Numeric", "SignedNumeric",
        "BinaryInteger", "FixedWidthInteger", "UnsignedInteger", "SignedInteger",
        "FloatingPoint", "BinaryFloatingPoint",
        // Standard Library - Collections
        "Sequence", "Collection", "IteratorProtocol", "BidirectionalCollection",
        "RandomAccessCollection", "MutableCollection", "RangeReplaceableCollection",
        "LazySequenceProtocol", "LazyCollectionProtocol",
        "SetAlgebra", "OptionSet",
        // Standard Library - Literals
        "ExpressibleByStringLiteral", "ExpressibleByExtendedGraphemeClusterLiteral",
        "ExpressibleByUnicodeScalarLiteral", "ExpressibleByIntegerLiteral",
        "ExpressibleByFloatLiteral", "ExpressibleByBooleanLiteral",
        "ExpressibleByArrayLiteral", "ExpressibleByDictionaryLiteral",
        "ExpressibleByNilLiteral", "ExpressibleByStringInterpolation",
        // Standard Library - Other
        "AnyObject", "AnyClass",
        // Combine
        "Publisher", "Subscriber", "Subscription", "Cancellable",
        "TopLevelEncoder", "TopLevelDecoder",
        "ObservableObjectProtocol",
        // Foundation
        "NSCopying", "NSMutableCopying", "NSCoding", "NSSecureCoding",
        "NSObjectProtocol",
    ]

    /// Apple SDKのクラスプレフィックス
    private static let appleSDKPrefixes = [
        "UI", "NS", "CG", "CA", "AV", "MK", "CL", "WK", "SK", "SCN", "MDL",
        "PH", "CN", "HK", "EK", "GK", "SF", "AS", "CM", "CK", "MP", "MT",
        "LA", "AU", "VN", "AR", "ML", "NL", "CT", "CI", "SL",
    ]

    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)
        let (protocols, superclass) = extractInheritance(from: node.inheritanceClause, typeKind: "Class")

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
        // Structは継承できないので、全てプロトコル
        let (protocols, _) = extractInheritance(from: node.inheritanceClause, typeKind: "Struct")

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
        // Enumは継承できないので、全てプロトコル
        let (protocols, _) = extractInheritance(from: node.inheritanceClause, typeKind: "Enum")

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
        // Actorは継承できないので、全てプロトコル
        let (protocols, _) = extractInheritance(from: node.inheritanceClause, typeKind: "Actor")

        typeConformances.append(SwiftSyntaxAnalyzer.TypeConformanceInfo(
            typeName: node.name.text,
            typeKind: "Actor",
            protocols: protocols,
            superclass: nil,
            line: location.line
        ))

        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)

        // Protocolが継承している他のProtocol（全てプロトコル）
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

    // MARK: - Private Methods

    /// 継承リストからプロトコルとスーパークラスを抽出
    /// - Parameters:
    ///   - clause: 継承句
    ///   - typeKind: 型の種類（Class, Struct, Enum, Actor）
    /// - Returns: (プロトコルリスト, スーパークラス)
    private func extractInheritance(
        from clause: InheritanceClauseSyntax?,
        typeKind: String
    ) -> (protocols: [String], superclass: String?) {
        guard let clause = clause else {
            return ([], nil)
        }

        let inheritedTypes = clause.inheritedTypes.map { $0.type.trimmedDescription }

        // Struct/Enum/Actor: 継承できないので、全てプロトコル（100%正確）
        if typeKind != "Class" {
            return (inheritedTypes, nil)
        }

        // Class: 多段階判定で最初の要素がスーパークラスかプロトコルか判別
        guard let first = inheritedTypes.first else {
            return ([], nil)
        }

        // 多段階判定フロー
        // 1. 既知のプロトコル → プロトコル
        if Self.knownProtocols.contains(first) {
            return (inheritedTypes, nil)
        }

        // 2. Apple SDKのクラスパターン → スーパークラス
        if isAppleSDKClass(first) {
            return (Array(inheritedTypes.dropFirst()), first)
        }

        // 3. 2文字大文字プレフィックス → スーパークラス（Apple SDK以外のUI*, NS*等）
        if hasUppercasePrefix(first, length: 2) {
            return (Array(inheritedTypes.dropFirst()), first)
        }

        // 4. 命名規則でプロトコルっぽい → プロトコル
        if isLikelyProtocol(first) {
            return (inheritedTypes, nil)
        }

        // 5. わからない → プロトコル（安全側に倒す）
        // プロトコル見落としよりスーパークラス見落としの方がマシ
        return (inheritedTypes, nil)
    }

    /// Apple SDKのクラスかどうか判定
    private func isAppleSDKClass(_ name: String) -> Bool {
        for prefix in Self.appleSDKPrefixes {
            if name.hasPrefix(prefix) && name.count > prefix.count {
                // プレフィックスの次の文字が大文字であることを確認（UIView, NSObject等）
                let index = name.index(name.startIndex, offsetBy: prefix.count)
                if name[index].isUppercase {
                    return true
                }
            }
        }
        return false
    }

    /// 2文字以上の大文字プレフィックスを持つか判定
    private func hasUppercasePrefix(_ name: String, length: Int) -> Bool {
        guard name.count > length else { return false }
        let prefix = name.prefix(length)
        return prefix.allSatisfy { $0.isUppercase }
    }

    /// 命名規則でプロトコルっぽいか判定
    private func isLikelyProtocol(_ name: String) -> Bool {
        // 典型的なプロトコル命名パターン
        name.hasSuffix("Protocol") ||
        name.hasSuffix("Delegate") ||
        name.hasSuffix("DataSource") ||
        name.hasSuffix("able") ||   // Sendable, Comparable, etc.
        name.hasSuffix("ible") ||   // Convertible, Accessible, etc.
        name.hasSuffix("ing") ||    // Encoding, etc.
        name.hasSuffix("Type") ||   // SomeType, etc.
        name.contains("Delegate") ||
        name.contains("DataSource")
    }
}
