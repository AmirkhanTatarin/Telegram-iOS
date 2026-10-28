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

    /// Public MTProto proxies checked from Moscow by our server, cached on the phone.
    public static let listURLs = ["https://dl.novastream.club:8443/stogram/proxies.json", "https://novastream.club/stogram/proxies.json"]
    private static let cacheKey = "stogramPublicProxies"
    private static let managedKey = "stogramManagedProxyHosts"

    public static var publicServers: [ProxyServerSettings] {
        guard let items = UserDefaults.standard.array(forKey: cacheKey) as? [String] else {
            return []
        }
        return items.compactMap(parse)
    }

    /// Everything Stogram may pick from: the fresh public list first, our own servers last.
    public static var candidates: [ProxyServerSettings] {
        var result = publicServers
        for server in servers where !result.contains(server) {
            result.append(server)
        }
        return result
    }

    /// Proxies Stogram itself put into the Telegram settings (so the user's own ones are never touched).
    public static func isManaged(_ server: ProxyServerSettings) -> Bool {
        if servers.contains(server) || publicServers.contains(server) {
            return true
        }
        let hosts = UserDefaults.standard.stringArray(forKey: managedKey) ?? []
        return hosts.contains("\(server.host):\(server.port)")
    }

    public static func markManaged(_ server: ProxyServerSettings) {
        var hosts = UserDefaults.standard.stringArray(forKey: managedKey) ?? []
        let key = "\(server.host):\(server.port)"
        if !hosts.contains(key) {
            hosts.append(key)
            UserDefaults.standard.set(Array(hosts.suffix(200)), forKey: managedKey)
        }
    }

    private static func parse(_ item: String) -> ProxyServerSettings? {
        let parts = item.split(separator: ":").map(String.init)
        guard parts.count == 3, let port = Int32(parts[1]), let secret = MTProxySecret.parse(parts[2]) else {
            return nil
        }
        return ProxyServerSettings(host: parts[0], port: port, connection: .mtp(secret: secret.serialize()))
    }

    /// Downloads the public list; completion on the main queue with true when it was updated.
    public static func refreshPublicList(completion: @escaping (Bool) -> Void) {
        func attempt(_ index: Int) {
            guard index < listURLs.count, let url = URL(string: listURLs[index]) else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15.0), completionHandler: { data, response, _ in
                guard let data, (response as? HTTPURLResponse)?.statusCode == 200, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let proxies = object["proxies"] as? [[String: Any]] else {
                    attempt(index + 1)
                    return
                }
                var items: [String] = []
                for proxy in proxies {
                    if let host = proxy["host"] as? String, let port = proxy["port"] as? Int, let secret = proxy["secret"] as? String, !host.contains(":") {
                        let item = "\(host):\(port):\(secret)"
                        if parse(item) != nil {
                            items.append(item)
                        }
                    }
                }
                if !items.isEmpty {
                    UserDefaults.standard.set(Array(items.prefix(25)), forKey: cacheKey)
                }
                DispatchQueue.main.async { completion(!items.isEmpty) }
            }).resume()
        }
        attempt(0)
    }

    /// Human name of one of our servers for the settings screen.
    public static func title(host: String) -> String {
        if let index = servers.firstIndex(where: { $0.host == host }) {
            return index == 0 ? "Stogram, Москва" : "Stogram, Европа"
        }
        if let index = publicServers.firstIndex(where: { $0.host == host }) {
            return "публичный №\(index + 1)"
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
                if let active = settings.activeServer, isManaged(active) {
                    settings.enabled = false
                }
                return settings
            }).start()
        }
    }
}
