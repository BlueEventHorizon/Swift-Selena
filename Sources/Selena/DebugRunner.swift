//
//  DebugRunner.swift
//  Swift-Selena
//
//  Created on 2025/10/23.
//

#if DEBUG
import Foundation
import Logging
import MCP

/// デバッグ用自動テストランナー（プロセス内実行）
///
/// ## 目的
/// MCPサーバーと同一プロセスで自動テストシーケンスを実行し、Xcodeデバッガでトレース
///
/// ## 特徴
/// - 起動N秒後に自動実行
/// - 本番と同じLSPState使用
/// - テストシーケンス自動実行
/// - Xcodeデバッガ完全対応
///
/// ## 使用方法
/// Xcodeで実行 → 5秒後に自動テスト開始
actor DebugRunner {
    private let lspState: LSPState
    private let logger: Logger

    init(lspState: LSPState, logger: Logger) {
        self.lspState = lspState
        self.logger = logger
    }

    /// 自動テストシーケンスを実行
    ///
    /// - Parameters:
    ///   - delay: 実行開始までの遅延時間（秒）
    ///   - lspState: 本番と共有するLSPState
    ///   - logger: ロガー
    static func run(
        delay: TimeInterval,
        lspState: LSPState,
        logger: Logger
    ) async {
        let runner = DebugRunner(lspState: lspState, logger: logger)
        await runner.executeTestSequence(delay: delay)
    }

    /// テストシーケンス実行
    private func executeTestSequence(delay: TimeInterval) async {
        logger.info("🔧 DebugRunner: Will start in \(delay) seconds...")

        // 遅延（MCPサーバー起動とLSP接続完了を待つ）
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        logger.info("🔧 DebugRunner: ========================================")
        logger.info("🔧 DebugRunner: Starting Automatic Test Sequence")
        logger.info("🔧 DebugRunner: ========================================")

        // テスト対象プロジェクト（Swift-Selena自身でテスト）
        // 実行時のカレントディレクトリまたは実行ファイルの場所から動的に取得
        let testProjectPath = Self.detectProjectPath()

        do {
            // ProjectMemory初期化
            logger.info("🔧 Step 1: Initializing ProjectMemory for \(testProjectPath)")
            let projectMemory = try ProjectMemory(projectPath: testProjectPath)
            logger.info("✅ ProjectMemory initialized")

            // LSP接続状態確認と接続試行
            logger.info("🔧 Step 2: Checking LSP status...")
            var lspAvailable = await lspState.isLSPAvailable()
            logger.info("LSP status: \(lspAvailable ? "✅ available" : "❌ not available")")

            if !lspAvailable {
                logger.info("🔧 LSP not available, attempting connection...")
                // LSP接続を試行
                lspAvailable = await lspState.tryConnect(projectPath: testProjectPath)

                if lspAvailable {
                    logger.info("✅ LSP connected successfully")
                } else {
                    logger.error("❌ LSP connection failed - tests will fail")
                    throw DebugRunnerError.lspNotAvailable
                }
            }

            // v0.5.4: LSP APIのテスト
            logger.info("🔧 Step 3: Testing LSP enhancements...")
            try await testDocumentSymbol(projectMemory: projectMemory)
            try await testTypeHierarchy(projectMemory: projectMemory)

            logger.info("🔧 ========================================")
            logger.info("✅ DebugRunner: All tests passed!")
            logger.info("🔧 ========================================")

        } catch {
            logger.error("🔧 ========================================")
            logger.error("❌ DebugRunner: Test sequence failed!")
            logger.error("Error: \(error)")
            logger.error("🔧 ========================================")

            // エラー詳細をログに出力
            if let mcpError = error as? MCPError {
                logger.error("MCP Error type: \(mcpError)")
            }
        }
    }

    /// documentSymbolテスト（v0.5.4）
    private func testDocumentSymbol(projectMemory: ProjectMemory) async throws {
        logger.info("🔧 Test v0.5.4: documentSymbol API")

        let projectPath = Self.detectProjectPath()
        let fullPath = (projectPath as NSString).appendingPathComponent("Sources/Selena/Core/ProjectMemory.swift")

        let filePath: MCP.Value = .string(fullPath)

        let params = CallTool.Parameters(
            name: "list_symbols",
            arguments: ["file_path": filePath]
        )

        let result = try await ListSymbolsTool.executeWithLSP(
            params: params,
            projectMemory: projectMemory,
            lspState: lspState,
            logger: logger
        )

        logger.info("✅ documentSymbol test completed")

        // 結果をログに出力（最初の200文字のみ）
        for content in result.content {
            if case .text(let text, _, _) = content {
                let preview = String(text.prefix(200))
                logger.info("   Result: \(preview)...")
            }
        }
    }

    /// typeHierarchyテスト（v0.5.4）
    private func testTypeHierarchy(projectMemory: ProjectMemory) async throws {
        logger.info("🔧 Test v0.5.4: typeHierarchy API")

        let typeName: MCP.Value = .string("ProjectMemory")

        let params = CallTool.Parameters(
            name: "get_type_hierarchy",
            arguments: ["type_name": typeName]
        )

        let result = try await GetTypeHierarchyTool.executeWithLSP(
            params: params,
            projectMemory: projectMemory,
            lspState: lspState,
            logger: logger
        )

        logger.info("✅ typeHierarchy test completed")

        // 結果をログに出力（最初の200文字のみ）
        for content in result.content {
            if case .text(let text, _, _) = content {
                let preview = String(text.prefix(200))
                logger.info("   Result: \(preview)...")
            }
        }
    }
}

enum DebugRunnerError: Error {
    case lspNotAvailable
}

// MARK: - Private Helpers

extension DebugRunner {
    /// プロジェクトパスを動的に検出
    ///
    /// 優先順位:
    /// 1. カレントディレクトリにPackage.swiftがある場合はカレントディレクトリ
    /// 2. 実行ファイルのパスから推測（.build/debug/Swift-Selena → プロジェクトルート）
    /// 3. フォールバック: カレントディレクトリ
    private static func detectProjectPath() -> String {
        let fileManager = FileManager.default
        let currentDir = fileManager.currentDirectoryPath

        // カレントディレクトリにPackage.swiftがあるか確認
        let packageSwiftPath = (currentDir as NSString).appendingPathComponent("Package.swift")
        if fileManager.fileExists(atPath: packageSwiftPath) {
            return currentDir
        }

        // 実行ファイルのパスから推測
        // 例: /path/to/project/.build/arm64-apple-macosx/debug/Swift-Selena
        //     → /path/to/project
        let executablePath = Bundle.main.executablePath ?? ""
        if executablePath.contains(".build/") {
            // .build/ より前の部分を取得
            if let range = executablePath.range(of: ".build/") {
                let projectRoot = String(executablePath[..<range.lowerBound])
                let trimmedPath = projectRoot.hasSuffix("/")
                    ? String(projectRoot.dropLast())
                    : projectRoot
                // Package.swiftが存在するか確認
                let packagePath = (trimmedPath as NSString).appendingPathComponent("Package.swift")
                if fileManager.fileExists(atPath: packagePath) {
                    return trimmedPath
                }
            }
        }

        // フォールバック: カレントディレクトリ
        return currentDir
    }
}
#endif
