# Repository Guidelines

## プロジェクト構成とモジュール
- ソース: `Sources/XSim`（エントリ）、`Sources/XSimCLI`（アプリ本体）
  - Commands: CLI サブコマンド（`ListCommand.swift`, `StartCommand.swift` など）
  - Services: simctl 連携（`SimulatorService.swift`）
  - Models: ドメイン型とエラー
- テスト: `Tests/XSimCLITests`（XCTest の統合テスト）
- 設定: `Package.swift`。整形は `Makefile` ターゲットで実行

## ビルド・テスト・実行
- ビルド: `swift build` — 全ターゲットをビルド。
- 実行: `swift run xsim list`（例: `swift run xsim boot "iPhone 15"`）。
- テスト: `swift test` — XCTest を実行。Xcode と `xcrun simctl` が必要。
- 整形: `make format` — SwiftFormat を実行。

## コーディング規約
- Swift API Design Guidelines に準拠。
  - 型/列挙/プロトコル: UpperCamelCase（`SimulatorService`）。
  - メソッド/変数/引数: lowerCamelCase（`startSimulator`）。
  - 原則 1 ファイル 1 主要型。可能ならファイル名=型名。
- インデント: スペース4。行は簡潔に。明示的なアクセス制御を推奨。
- push 前に必ず `make format` を実行。

## テスト方針
- フレームワーク: XCTest（`Tests/XSimCLITests`）。
- 命名: シナリオ重視（例: `testStartSimulatorWithValidDevice`）。
- 範囲: Models はユニット、Services/Commands は統合寄りでも可。
- 環境: `simctl` を呼ぶため Xcode CLT とシミュレータが必要。利用不可なら一部は `XCTSkip` を検討。

## コミットとPR
- コミット: Conventional Commits を推奨（`feat:`, `fix:`, `chore:`）。命令形・スコープ明確に。
- PR には次を含める:
  - 変更概要（What/Why）と関連 Issue
  - CLI 実行例（例: `swift run xsim list` の出力）
  - 影響範囲/リスクと手動検証手順

## 環境とTips
- 要件: macOS 10.15+、Xcode CLT、`xcrun simctl` が PATH にあること。
- CLI の振る舞いを変更したら `README.md` の例も更新。
- Command は薄く、プロセス/`simctl` ロジックは `SimulatorService`、ドメインは Models に置く。
