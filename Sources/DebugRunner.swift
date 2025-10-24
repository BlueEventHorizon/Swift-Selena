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
        let testProjectPath = "/Users/k_terada/data/dev/_WORKING_/apps/Swift-Selena"

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

            // テストシーケンス実行
            logger.info("🔧 Step 3: Running test sequence...")

            try await testFindSymbolReferencesSequence(projectMemory: projectMemory)

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

    /// find_symbol_references連続実行テスト
    private func testFindSymbolReferencesSequence(projectMemory: ProjectMemory) async throws {
        // Swift-Selena自身のファイルでテスト（参照が確実にあるシンボル）
        let testCases: [(file: String, line: Int, column: Int, description: String)] = [
            ("Sources/LSP/LSPClient.swift", 30, 7, "LSPClient class"),
            ("Sources/LSP/LSPState.swift", 34, 7, "LSPState actor"),
            ("Sources/ProjectMemory.swift", 12, 7, "ProjectMemory class"),
            ("Sources/Tools/LSP/FindSymbolReferencesTool.swift", 48, 6, "FindSymbolReferencesTool"),
            ("Sources/SwiftMCPServer.swift", 8, 8, "SwiftMCPServer struct")
        ]

        for (index, testCase) in testCases.enumerated() {
            let round = index + 1
            logger.info("🔧 Test \(round)/\(testCases.count): \(testCase.description) at \(testCase.file):\(testCase.line):\(testCase.column)")

            try await testFindSymbolReferences(
                projectMemory: projectMemory,
                round: round,
                file: testCase.file,
                line: testCase.line,
                column: testCase.column
            )

            // 各テスト間に少し待機
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5秒
        }
    }

    /// find_symbol_references単体テスト
    private func testFindSymbolReferences(
        projectMemory: ProjectMemory,
        round: Int,
        file: String,
        line: Int,
        column: Int
    ) async throws {
        // フルパス作成
        let fullPath = "/Users/k_terada/data/dev/_WORKING_/apps/Swift-Selena/\(file)"

        // MCPのValue型で引数を作成
        let filePath: MCP.Value = .string(fullPath)
        let lineValue: MCP.Value = .init(integerLiteral: line)
        let columnValue: MCP.Value = .init(integerLiteral: column)

        let params = CallTool.Parameters(
            name: "find_symbol_references",
            arguments: [
                "file_path": filePath,
                "line": lineValue,
                "column": columnValue
            ]
        )

        // ここにブレークポイントを設定可能
        let result = try await FindSymbolReferencesTool.execute(
            params: params,
            projectMemory: projectMemory,
            lspState: lspState,
            logger: logger
        )

        logger.info("✅ Round \(round) completed")

        // 結果をログに出力
        for content in result.content {
            if case .text(let text) = content {
                logger.info("   Result: \(text.replacingOccurrences(of: "\n", with: " "))")
            }
        }
    }
}

enum DebugRunnerError: Error {
    case lspNotAvailable
}
#endif
