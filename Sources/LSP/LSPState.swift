//
//  LSPState.swift
//  Swift-Selena
//
//  Created on 2025/10/21.
//

import Foundation
import Logging

/// LSP接続状態を管理するActor
///
/// ## 目的
/// SourceKit-LSPの接続状態をスレッドセーフに管理
///
/// ## 機能
/// - LSP接続の試行
/// - 接続状態の問い合わせ
/// - LSPClientインスタンスの取得
/// - 接続の切断
///
/// ## スレッドセーフ
/// Actorで実装されているため、並行アクセスが安全
///
/// ## 使用例
/// ```swift
/// let lspState = LSPState(logger: logger)
/// let connected = await lspState.tryConnect(projectPath: "/path/to/project")
/// if await lspState.isLSPAvailable() {
///     let client = await lspState.getClient()
///     // LSP機能を使用
/// }
/// ```
actor LSPState {
    private var isAvailable: Bool = false
    private var lspClient: LSPClient?
    private let logger: Logger

    /// 初期化
    ///
    /// - Parameter logger: ロガー
    init(logger: Logger) {
        self.logger = logger
    }

    /// LSP接続を試みる
    ///
    /// ## 処理フロー
    /// 1. 直接LSPClient起動を試行
    /// 2. 成功 = LSP利用可能
    /// 3. 失敗 = LSP利用不可（理由は問わない）
    ///
    /// ## 失敗する理由（全て同じ扱い）
    /// - ビルド未実施
    /// - ビルドエラー
    /// - sourcekit-lsp未インストール
    /// - プロジェクト設定不正
    ///
    /// - Parameter projectPath: プロジェクトパス
    /// - Returns: 接続成功したか
    func tryConnect(projectPath: String) async -> Bool {
        logger.info("Attempting LSP connection for: \(projectPath)")

        // 直接LSP接続試行（BuildChecker削除）
        do {
            let client = try await LSPClient(projectPath: projectPath, logger: logger)
            lspClient = client
            isAvailable = true
            logger.info("✅ LSP connected successfully")
            return true
        } catch {
            logger.info("ℹ️ LSP connection failed: \(error.localizedDescription)")
            logger.info("ℹ️ Using SwiftSyntax only")
            isAvailable = false
            return false
        }
    }

    /// LSPが利用可能か
    ///
    /// - Returns: LSP利用可能ならtrue
    func isLSPAvailable() -> Bool {
        return isAvailable
    }

    /// LSPClientを取得
    ///
    /// - Returns: LSPClientインスタンス（利用不可の場合nil）
    func getClient() -> LSPClient? {
        return lspClient
    }

    /// LSP接続を切断
    func disconnect() async {
        if let client = lspClient {
            client.disconnect()
            logger.info("LSP disconnected")
        }
        lspClient = nil
        isAvailable = false
    }
}
