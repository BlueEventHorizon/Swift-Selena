#!/usr/bin/env swift

import Foundation

// テスト用の一時ディレクトリパスを取得
let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cache-test-\(UUID().uuidString)")

print("🧪 Cache System Manual Test")
print("Temp directory: \(tempDir.path)")
print("")

// Swift製のCacheManagerを直接テストすることはできないため、
// 以下の手動テスト手順を実行してください

print("📋 Manual Test Steps:")
print("")

print("Test 1: Basic Cache Operations")
print("  1. MCPサーバーを起動")
print("  2. initialize_projectを実行")
print("  3. analyze_importsを実行（初回 - キャッシュ構築）")
print("  4. ~/.swift-selena/clients/default/projects/Swift-Selena-xxx/cache.jsonが作成されることを確認")
print("  5. analyze_importsを再実行（2回目 - キャッシュヒット）")
print("  Expected: 2回目は高速")
print("")

print("Test 2: File Modification Detection")
print("  1. Tests/Fixtures/TestImports.swiftを編集")
print("  2. analyze_importsを実行")
print("  Expected: TestImports.swiftのみ再解析、他はキャッシュから")
print("")

print("Test 3: File Deletion (Garbage Collection)")
print("  1. 新規ファイルを作成: Tests/Fixtures/TempFile.swift")
print("  2. analyze_importsを実行（TempFileがキャッシュに追加される）")
print("  3. TempFile.swiftを削除")
print("  4. analyze_importsを100回実行（GCトリガー）")
print("  Expected: TempFileのキャッシュエントリが削除される")
print("")

print("Test 4: Cache Stats")
print("  1. cache.jsonを開いて内容を確認")
print("  2. fileCacheの各エントリを確認")
print("  Expected: lastModified, lastAccessed, imports等が正しく保存されている")
print("")

print("✅ Test instructions complete")
print("")
print("実行方法:")
print("  1. Claude Codeを再起動")
print("  2. 上記の手順を実行")
print("  3. 結果を報告")
