# コントリビューション

Issue、Pull Request を歓迎します！

ビルド・セットアップ・使い方は [README](README.ja.md) を参照してください。

English version: [CONTRIBUTING.md](CONTRIBUTING.md)

## リリース手順（メンテナ向け）

バージョン更新と Homebrew Formula の更新手順です。**正規かつ実行可能な手順は [CLAUDE.md](CLAUDE.md)**（release 運用順序のセクション）を出典とし、以下の図は理解補助です。

> **3 つの肝**
> 1. `git rev-parse HEAD` で **①の SHA を merge 前に確定**する（だから Formula を先に書ける）
> 2. Formula の `revision` に **①の SHA** を書き、**tag も①に打つ**（merge commit ではない）
> 3. main へは **`--no-ff` マージ**（squash / rebase は①の SHA が消えるため不可）

### フロー図（手順チェックリスト）

```mermaid
flowchart TD
    subgraph PH1["Phase 1 — bump PR（develop・単一PRに同梱）"]
        A["① commit: Constants + CHANGELOG bump<br/>（/forge:update-version）"]
        B["git rev-parse HEAD<br/>→ ①の SHA を取得"]
        C["② commit: Formula を更新<br/>tag=0.6.12 / revision=①SHA"]
        D["verify_version_consistency.sh<br/>＋ brew style"]
        E["push → PR 作成・マージ"]
    end

    subgraph PH2["Phase 2 — main マージ ＋ tag（main・マージ1回）"]
        F["develop を main に --no-ff マージ<br/>①の SHA を保存（squash/rebase 不可）"]
        G["git tag 0.6.12 を ①の commit に作成<br/>（merge commit でない）→ push"]
        H{"rev-parse 0.6.12<br/>== Formula revision ?"}
        K["tag を削除して切り直す<br/>git tag -d → 正しい①で再作成"]
        I["brew install --build-from-source"]
        J["serverInfo.version == 0.6.12<br/>drift 解消 ✓"]
    end

    A --> B --> C --> D --> E --> F --> G --> H
    H -->|一致| I --> J
    H -->|不一致| K --> G

    style B fill:#fff3cd
    style C fill:#fff3cd
    style F fill:#ffe0e0
    style G fill:#fff3cd
```

### シーケンス図（時系列と「なぜ」）

```mermaid
sequenceDiagram
    participant Y as あなた / AI
    participant D as develop
    participant M as main
    participant T as tag 0.6.12
    participant BR as brew install

    rect rgb(230, 245, 255)
    Note over Y,D: Phase 1 — bump PR（develop・単一PRに同梱）
    Y->>D: ① commit … Constants + CHANGELOG bump（/forge:update-version）
    Y->>D: git rev-parse HEAD で ①の SHA を取得
    Note over Y,D: ★ ①の SHA が merge 前に確定 → Formula に書ける
    Y->>D: ② commit … Formula を tag=0.6.12 / revision=①SHA に更新
    Y->>D: verify + brew style → push → PR マージ
    end

    rect rgb(232, 245, 233)
    Note over Y,M: Phase 2 — main マージ + tag（main・マージは1回）
    Y->>M: develop を --no-ff マージ（①の SHA を保存／squash 不可）
    Y->>T: git tag 0.6.12 を ①の commit に作成（merge commit でない）
    T-->>Y: rev-parse 0.6.12 == Formula revision を確認
    end

    Y->>BR: brew install --build-from-source
    BR->>M: 最新 Formula を読む（tag=0.6.12 / revision=①SHA）
    BR->>T: revision=①SHA のソースを取得しビルド
    BR-->>Y: serverInfo.version == 0.6.12 ✓（drift 解消）
```
