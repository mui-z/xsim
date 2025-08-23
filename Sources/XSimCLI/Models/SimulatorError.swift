import Foundation

/// Custom error types for simulator operations
public enum SimulatorError: Error, LocalizedError, Equatable {
    /// Device with the specified identifier was not found
    case deviceNotFound(String)

    /// Device is already running
    case deviceAlreadyRunning(String)

    /// Device is not currently running
    case deviceNotRunning(String)

    /// Invalid device type specified
    case invalidDeviceType(String)

    /// Invalid runtime specified
    case invalidRuntime(String)

    /// App bundle was not found at the specified path
    case appBundleNotFound(String)

    /// simctl command execution failed
    case simctlCommandFailed(String)

    /// Insufficient permissions to perform the operation
    case insufficientPermissions

    /// No devices are available
    case noDevicesAvailable

    /// Invalid device identifier format
    case invalidDeviceIdentifier(String)

    /// Operation timed out
    case operationTimeout

    /// Xcode command line tools are not installed
    case xcodeToolsNotInstalled

    public var errorDescription: String? {
        switch self {
        case let .deviceNotFound(identifier):
            "指定されたデバイス '\(identifier)' が見つかりません。利用可能なデバイスを確認するには 'xsim list' を実行してください。"

        case let .deviceAlreadyRunning(identifier):
            "デバイス '\(identifier)' は既に起動しています。"

        case let .deviceNotRunning(identifier):
            "デバイス '\(identifier)' は起動していません。"

        case let .invalidDeviceType(deviceType):
            "無効なデバイスタイプ '\(deviceType)' が指定されました。利用可能なデバイスタイプを確認するには 'xsim create --list-types' を実行してください。"

        case let .invalidRuntime(runtime):
            "無効なランタイム '\(runtime)' が指定されました。利用可能なランタイムを確認するには 'xsim create --list-runtimes' を実行してください。"

        case let .appBundleNotFound(path):
            "指定されたパス '\(path)' にアプリバンドルが見つかりません。パスが正しいか確認してください。"

        case let .simctlCommandFailed(message):
            "simctlコマンドの実行に失敗しました: \(message)"

        case .insufficientPermissions:
            "操作を実行するための権限が不足しています。管理者権限で実行してください。"

        case .noDevicesAvailable:
            "利用可能なデバイスがありません。新しいシミュレータを作成するには 'xsim create' を使用してください。"

        case let .invalidDeviceIdentifier(identifier):
            "無効なデバイス識別子 '\(identifier)' が指定されました。デバイス名またはUUIDを指定してください。"

        case .operationTimeout:
            "操作がタイムアウトしました。しばらく待ってから再試行してください。"

        case .xcodeToolsNotInstalled:
            "Xcode Command Line Toolsがインストールされていません。'xcode-select --install' を実行してインストールしてください。"
        }
    }

    public var failureReason: String? {
        switch self {
        case .deviceNotFound:
            "指定されたデバイスが存在しません"
        case .deviceAlreadyRunning:
            "デバイスは既に起動状態です"
        case .deviceNotRunning:
            "デバイスが停止状態です"
        case .invalidDeviceType:
            "サポートされていないデバイスタイプです"
        case .invalidRuntime:
            "サポートされていないランタイムです"
        case .appBundleNotFound:
            "アプリバンドルが見つかりません"
        case .simctlCommandFailed:
            "simctlコマンドの実行エラー"
        case .insufficientPermissions:
            "権限不足"
        case .noDevicesAvailable:
            "利用可能なデバイスがありません"
        case .invalidDeviceIdentifier:
            "無効なデバイス識別子"
        case .operationTimeout:
            "操作タイムアウト"
        case .xcodeToolsNotInstalled:
            "Xcode Command Line Toolsが未インストール"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .deviceNotFound:
            "'xsim list' で利用可能なデバイスを確認してください"
        case .deviceAlreadyRunning:
            "デバイスは既に起動しているため、操作は不要です"
        case .deviceNotRunning:
            "'xsim start <device>' でデバイスを起動してください"
        case .invalidDeviceType:
            "'xsim create --list-types' で利用可能なデバイスタイプを確認してください"
        case .invalidRuntime:
            "'xsim create --list-runtimes' で利用可能なランタイムを確認してください"
        case .appBundleNotFound:
            "アプリバンドルのパスが正しいか確認してください"
        case .simctlCommandFailed:
            "Xcodeが正しくインストールされているか確認してください"
        case .insufficientPermissions:
            "管理者権限で実行するか、ファイルの権限を確認してください"
        case .noDevicesAvailable:
            "'xsim create' で新しいシミュレータを作成してください"
        case .invalidDeviceIdentifier:
            "デバイス名またはUUIDを正しく指定してください"
        case .operationTimeout:
            "しばらく待ってから再試行してください"
        case .xcodeToolsNotInstalled:
            "'xcode-select --install' を実行してXcode Command Line Toolsをインストールしてください"
        }
    }
}
