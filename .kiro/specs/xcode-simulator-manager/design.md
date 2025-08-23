# 設計書

## 概要

Xcode Simulator管理CLIツール「xsim」は、既存のSwiftCLIフレームワークを使用して構築されます。このツールは、複雑で長いsimctlコマンドを短くて覚えやすいコマンドでラップし、開発者の生産性を向上させます。

## アーキテクチャ

### 全体構成

```
xsim
├── CLI Layer (SwiftCLI)
├── Command Layer (各コマンドクラス)
├── Service Layer (SimulatorService)
├── Model Layer (データモデル)
└── Utility Layer (共通処理)
```

### 依存関係

- **SwiftCLI**: コマンドライン引数の解析とコマンド実行
- **Foundation**: プロセス実行とJSON解析
- **Rainbow**: カラー出力（既存プロジェクトから継承）

## コンポーネントと インターフェース

### 1. メインCLIクラス

```swift
public class XSimCLI {
    public func run() -> Never
}
```

### 2. コマンドクラス群

各要件に対応するコマンドクラス：

- `ListCommand`: シミュレータ一覧表示
- `StartCommand`: シミュレータ起動
- `StopCommand`: シミュレータ停止
- `ResetCommand`: シミュレータリセット
- `InstallCommand`: アプリインストール
- `CreateCommand`: シミュレータ作成
- `DeleteCommand`: シミュレータ削除

### 3. SimulatorServiceクラス

simctlコマンドとの実際のやり取りを担当：

```swift
class SimulatorService {
    func listDevices() throws -> [SimulatorDevice]
    func startSimulator(identifier: String) throws
    func stopSimulator(identifier: String?) throws
    func resetSimulator(identifier: String) throws
    func installApp(bundlePath: String, deviceId: String) throws
    func createSimulator(name: String, deviceType: String, runtime: String) throws -> String
    func deleteSimulator(identifier: String) throws
    func getAvailableDeviceTypes() throws -> [DeviceType]
    func getAvailableRuntimes() throws -> [Runtime]
}
```

## データモデル

### SimulatorDevice

```swift
struct SimulatorDevice {
    let udid: String
    let name: String
    let state: SimulatorState
    let deviceTypeIdentifier: String
    let runtimeIdentifier: String
    let isAvailable: Bool
}

enum SimulatorState: String, CaseIterable {
    case shutdown = "Shutdown"
    case booted = "Booted"
    case booting = "Booting"
    case shuttingDown = "Shutting Down"
}
```

### DeviceType

```swift
struct DeviceType {
    let identifier: String
    let name: String
}
```

### Runtime

```swift
struct Runtime {
    let identifier: String
    let name: String
    let version: String
    let isAvailable: Bool
}
```

## コマンド設計

### 短縮コマンド設計

simctlの長いコマンドを短縮：

| 機能 | simctl | 新コマンド |
|------|--------|-----------|
| 一覧表示 | `xcrun simctl list devices` | `xsim list` |
| 起動 | `xcrun simctl boot <device>` | `xsim start <device>` |
| 停止 | `xcrun simctl shutdown <device>` | `xsim stop [device]` |
| リセット | `xcrun simctl erase <device>` | `xsim reset <device>` |
| インストール | `xcrun simctl install <device> <app>` | `xsim install <device> <app>` |
| 作成 | `xcrun simctl create <name> <type> <runtime>` | `xsim create <name> <type> <runtime>` |
| 削除 | `xcrun simctl delete <device>` | `xsim delete <device>` |

### コマンド詳細設計

#### ListCommand
```swift
class ListCommand: Command {
    let name = "list"
    let shortDescription = "利用可能なシミュレータを一覧表示"
    
    @Flag("-r", "--running")
    var showRunningOnly: Bool
    
    @Flag("-a", "--available")  
    var showAvailableOnly: Bool
}
```

#### StartCommand
```swift
class StartCommand: Command {
    let name = "start"
    let shortDescription = "シミュレータを起動"
    
    @Param
    var deviceIdentifier: String
}
```

#### CreateCommand
```swift
class CreateCommand: Command {
    let name = "create"
    let shortDescription = "新しいシミュレータを作成"
    
    @Param
    var name: String
    
    @Param  
    var deviceType: String
    
    @Param
    var runtime: String
    
    @Flag("--list-types")
    var listDeviceTypes: Bool
    
    @Flag("--list-runtimes")
    var listRuntimes: Bool
}
```

## エラーハンドリング

### エラータイプ定義

```swift
enum SimulatorError: Error, LocalizedError {
    case deviceNotFound(String)
    case deviceAlreadyRunning(String)
    case deviceNotRunning(String)
    case invalidDeviceType(String)
    case invalidRuntime(String)
    case appBundleNotFound(String)
    case simctlCommandFailed(String)
    case insufficientPermissions
    
    var errorDescription: String? {
        // 日本語エラーメッセージ
    }
}
```

### エラー処理戦略

1. **Graceful Degradation**: simctlが利用できない場合の適切なメッセージ表示
2. **User-Friendly Messages**: 技術的なエラーを分かりやすい日本語メッセージに変換
3. **Suggestion Providing**: エラー時に次に取るべきアクションを提案

## テスト戦略

### 単体テスト

1. **SimulatorServiceテスト**
   - simctlコマンドの実行結果をモック
   - 各メソッドの正常系・異常系テスト

2. **コマンドクラステスト**
   - 引数解析のテスト
   - エラーハンドリングのテスト

3. **データモデルテスト**
   - JSON解析のテスト
   - バリデーションのテスト

### 統合テスト

1. **実際のsimctlとの連携テスト**
   - CI環境でのシミュレータ操作テスト
   - エラーケースの検証

### テスト実行環境

- macOS環境でのみ実行
- Xcode Simulatorが利用可能な環境
- GitHub Actionsでの自動テスト実行

## パフォーマンス考慮事項

### 応答性の向上

1. **並列処理**: 複数シミュレータの操作時の並列実行
2. **プログレス表示**: 時間のかかる操作での進捗表示

### リソース使用量

1. **メモリ効率**: 大量のシミュレータデータの効率的な処理
2. **プロセス管理**: simctlプロセスの適切な管理と終了

## セキュリティ考慮事項

1. **入力検証**: ユーザー入力の適切なサニタイズ
2. **パス検証**: アプリバンドルパスの安全性確認
3. **権限チェック**: 必要な権限の事前確認