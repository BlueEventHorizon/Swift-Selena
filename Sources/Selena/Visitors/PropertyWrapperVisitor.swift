//
//  PropertyWrapperVisitor.swift
//  SwiftMCPServer
//
//  Created by k_terada on 2025/10/03.
//

import SwiftSyntax

/// SwiftUI Property Wrapper（@State, @Binding等）を抽出するVisitor
class PropertyWrapperVisitor: SyntaxVisitor {
    var propertyWrappers: [SwiftSyntaxAnalyzer.PropertyWrapperInfo] = []
    let converter: SourceLocationConverter

    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.startLocation(converter: converter)

        // 属性をチェック（@State, @Binding 等）
        for attribute in node.attributes {
            if let customAttribute = attribute.as(AttributeSyntax.self) {
                let wrapperType = customAttribute.attributeName.trimmedDescription

                // 既知のSwiftUIプロパティラッパーのみ処理
                let knownWrappers = ["State", "Binding", "ObservedObject", "StateObject",
                                    "EnvironmentObject", "Environment", "Published",
                                    "FetchRequest", "AppStorage", "SceneStorage",
                                    "ObservationTracked", "ObservationIgnored"]

                if knownWrappers.contains(wrapperType) {
                    for binding in node.bindings {
                        if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                            let typeName = binding.typeAnnotation?.type.trimmedDescription
                            propertyWrappers.append(SwiftSyntaxAnalyzer.PropertyWrapperInfo(
                                propertyName: identifier.identifier.text,
                                wrapperType: wrapperType,
                                typeName: typeName,
                                line: location.line
                            ))
                        }
                    }
                }
            }
        }

        return .visitChildren
    }
}
