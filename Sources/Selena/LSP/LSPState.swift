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
    private var lspClients: [String: LSPClient] = [:]  // プロジェクトパスごとにLSPClient保持
    private var currentProjectPath: String?
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
    /// 1. Xcodeプロジェクト検出（.xcodeprojがあればLSP無効）
    /// 2. 既存接続をチェック（同じプロジェクトなら再利用）
    /// 3. 新規の場合、LSPClient起動を試行
    /// 4. 成功 = LSP利用可能
    /// 5. 失敗 = LSP利用不可（理由は問わない）
    ///
    /// ## 失敗する理由（全て同じ扱い）
    /// - Xcodeプロジェクト（グローバルインデックス不可）
    /// - ビルド未実施
    /// - ビルドエラー
    /// - sourcekit-lsp未インストール
    /// - プロジェクト設定不正
    ///
    /// - Parameter projectPath: プロジェクトパス
    /// - Returns: 接続成功したか
    func tryConnect(projectPath: String) async -> Bool {
        // Xcodeプロジェクト検出: .xcodeprojがあればLSPを無効化
        // 理由: SourceKit-LSPはXcodeプロジェクトでグローバルインデックスが動作しない（Issue #730）
        let projectURL = URL(fileURLWithPath: projectPath)
        if let contents = try? FileManager.default.contentsOfDirectory(at: projectURL, includingPropertiesForKeys: nil),
           contents.contains(where: { $0.pathExtension == "xcodeproj" }) {
            logger.info("ℹ️ Xcode project detected - LSP disabled (known limitation: Issue #730)")
            return false
        }

        // 既に同じプロジェクトに接続済みか確認
        if lspClients[projectPath] != nil {
            logger.info("✅ LSP already connected for: \(projectPath)")
            currentProjectPath = projectPath
            return true
        }

        logger.info("Attempting LSP connection for: \(projectPath)")

        // 直接LSP接続試行
        do {
            let client = try await LSPClient(projectPath: projectPath, logger: logger)
            lspClients[projectPath] = client
            currentProjectPath = projectPath
            logger.info("✅ LSP connected successfully")
            return true
        } catch {
            logger.info("ℹ️ LSP connection failed: \(error.localizedDescription)")
            logger.info("ℹ️ Using SwiftSyntax only")
            return false
        }
    }

    /// LSPが利用可能か
    ///
    /// - Returns: LSP利用可能ならtrue
    func isLSPAvailable() -> Bool {
        guard let projectPath = currentProjectPath else {
            return false
        }
        return lspClients[projectPath] != nil
    }

    /// LSPClientを取得
    ///
    /// - Returns: LSPClientインスタンス（利用不可の場合nil）
    func getClient() -> LSPClient? {
        guard let projectPath = currentProjectPath else {
            return nil
        }
        return lspClients[projectPath]
    }

    /// 特定プロジェクトのLSP接続を切断
    func disconnect(projectPath: String) async {
        if let client = lspClients[projectPath] {
            client.disconnect()
            logger.info("LSP disconnected for: \(projectPath)")
            lspClients.removeValue(forKey: projectPath)
        }
        if currentProjectPath == projectPath {
            currentProjectPath = nil
        }
    }

    /// 全てのLSP接続を切断
    func disconnectAll() async {
        for (projectPath, client) in lspClients {
            client.disconnect()
            logger.info("LSP disconnected for: \(projectPath)")
        }
        lspClients.removeAll()
        currentProjectPath = nil
    }
}
