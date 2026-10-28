import Foundation
import SwiftSignalKit
import TelegramCore
import MtProtoKit
import SGConfig
import SGSimpleSettings

/// Stogram: our built-in proxies and their last measured ping (shared by the settings screen and the proxy manager).
public enum StogramProxy {
    public struct Status: Equatable {
        public let host: String
        public let ping: Double?

        public init(host: String, ping: Double?) {
            self.host = host
            self.ping = ping
        }
    }

    /// From the build: sg_config "stogram_proxy" = "host:port:secret,host:port:secret".
    public static let servers: [ProxyServerSettings] = {
        guard let raw = SG_CONFIG.stogramProxy else {
            return []
        }
        var result: [ProxyServerSettings] = []
        for item in raw.split(separator: ",") {
            let parts = item.split(separator: ":").map(String.init)
            if parts.count == 3, let port = Int32(parts[1]), let secret = MTProxySecret.parse(parts[2]) {
                result.append(ProxyServerSettings(host: parts[0], port: port, connection: .mtp(secret: secret.serialize())))
            }
        }
        return result
    }()

    public static let current = Atomic<Status?>(value: nil)

    /// Human name of one of our servers for the settings screen.
    public static func title(host: String) -> String {
        if let index = servers.firstIndex(where: { $0.host == host }) {
            return index == 0 ? "Москва" : "Европа \(index)"
        }
        return host
    }

    /// The switch "Прокси Stogram": off also turns our proxy off right away.
    public static func setEnabled(_ enabled: Bool, accountManager: AccountManager<TelegramAccountManagerTypes>) {
        SGSimpleSettings.shared.stogramProxyAuto = enabled
        if !enabled {
            let _ = current.swap(nil)
            let _ = updateProxySettingsInteractively(accountManager: accountManager, { settings in
                var settings = settings
                if let active = settings.activeServer, servers.contains(active) {
                    settings.enabled = false
                }
                return settings
            }).start()
        }
    }
}
