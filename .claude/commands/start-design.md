---
argument-hint: <feature> (例: main, csv_import)
description: 設計書作成ワークフロー
allowed-tools: Bash(ls:*)
---

# 設計書作成ワークフロー・開始コマンド

## 概要

要件定義書から、設計書を作成するワークフローを起動する

## Feature選択 [MANDATORY]

対象Feature: **$ARGUMENTS**

引数が指定されていない場合は、以下を実行：
1. `project/` ディレクトリ内のFeature一覧を確認: !`ls -d project/*/`
2. ユーザーに対象Featureを質問

## 実行モード判定 [MANDATORY]

`project/{feature}/design/` ディレクトリを確認し、モードを決定：

| 状況 | モード |
|------|--------|
| 設計書が存在しない | **新規作成モード**: workflowに従って設計書を作成 |
| 設計書が存在する | **レビューモード**: 既存設計書をworkflowに沿ってレビューし、改善提案を出す |

## 必須参照文書 [MANDATORY]

**NEVER skip.** 下記を全て読み込み、深く理解すること

- `docs/workflow/plan/design_workflow.md`

## 実行

`docs/workflow/plan/design_workflow.md`

に従って作業を実施してください。
