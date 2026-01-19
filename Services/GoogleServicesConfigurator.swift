#if canImport(Foundation)
import Foundation
#endif

/// 旧 Google Maps / Places 初期化ユーティリティ（Apple Maps 移行後はダミー）
/// - 今後別プロバイダを差し込みたい場合のインターフェース保持目的
@MainActor
final class GoogleServicesConfigurator {
    static let shared = GoogleServicesConfigurator()

    private var didConfigure = false

    private init() {}

    /// 互換: 以前の初期化呼び出しを安全に無視する
    func configureIfNeeded() {
        guard !didConfigure else { return }
        print("� GoogleServicesConfigurator: no-op (Apple Maps 使用中)")
        didConfigure = true
    }

    /// Google Maps を利用可能かどうか
    var isMapsAvailable: Bool {
        false
    }

    /// Google Places Autocomplete を利用可能かどうか
    var isPlacesAvailable: Bool {
        false
    }
}
