import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import AccountContext
import SGSimpleSettings
import SGSettingsUI

/// Stogram: built-in proxies, so Telegram works without a VPN.
///
/// Our servers come from the build (sg_config "stogram_proxy": "host:port:secret,host:port:secret").
/// Every two minutes, and whenever the app comes back to the screen, all of them are pinged and the
/// fastest working one quietly becomes the active proxy. A proxy the user added himself is never replaced.
/// The switch "Прокси Stogram" (stogramProxyAuto) turns all of this off.
final class NovaProxyManager {
    private let context: AccountContext
    private var statuses: ProxyServersStatuses?
    private let statusesDisposable = MetaDisposable()
    private var settingsDisposable: Disposable?
    private var settings: ProxySettings = ProxySettings.defaultSettings
    private var timer: SwiftSignalKit.Timer?
    private var activeObserver: NSObjectProtocol?

    init(context: AccountContext) {
        self.context = context
        self.settingsDisposable = (context.sharedContext.accountManager.sharedData(keys: [SharedDataKeys.proxySettings])
        |> map { sharedData -> ProxySettings in
            return sharedData.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? ProxySettings.defaultSettings
        }
        |> deliverOnMainQueue).start(next: { [weak self] settings in
            self?.settings = settings
        })

        let timer = SwiftSignalKit.Timer(timeout: 120.0, repeat: true, completion: { [weak self] in
            self?.measure()
        }, queue: Queue.mainQueue())
        self.timer = timer
        timer.start()
        self.activeObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.measure()
        })
        Queue.mainQueue().after(2.0, { [weak self] in
            self?.measure()
        })
    }

    deinit {
        self.statusesDisposable.dispose()
        self.settingsDisposable?.dispose()
        self.timer?.invalidate()
        if let activeObserver = self.activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
    }

    private func isOurs(_ server: ProxyServerSettings?) -> Bool {
        guard let server else {
            return false
        }
        return StogramProxy.isManaged(server)
    }

    private var lastListRefresh: Double = 0.0

    private func measure() {
        guard SGSimpleSettings.shared.stogramProxyAuto else {
            return
        }
        // The public list goes stale fast: refresh it every 30 minutes, then measure again.
        let now = CFAbsoluteTimeGetCurrent()
        if now - self.lastListRefresh > 30.0 * 60.0 {
            self.lastListRefresh = now
            StogramProxy.refreshPublicList(completion: { [weak self] updated in
                if updated {
                    self?.measure()
                }
            })
        }
        let servers = StogramProxy.candidates
        guard !servers.isEmpty else {
            return
        }
        let statuses = ProxyServersStatuses(network: self.context.account.network, servers: .single(servers))
        self.statuses = statuses
        self.statusesDisposable.set((statuses.statuses()
        |> deliverOnMainQueue).start(next: { [weak self] values in
            self?.apply(values)
        }))
    }

    private func apply(_ values: [ProxyServerSettings: ProxyServerStatus]) {
        guard SGSimpleSettings.shared.stogramProxyAuto else {
            return
        }
        let settings = self.settings
        // The user's own proxy wins: leave it alone.
        if settings.enabled, let active = settings.activeServer, !self.isOurs(active) {
            return
        }
        var best: (ProxyServerSettings, Double)?
        var stillChecking = false
        for (server, status) in values {
            switch status {
            case let .available(ping):
                if best == nil || ping < best!.1 {
                    best = (server, ping)
                }
            case .checking:
                stillChecking = true
            case .notAvailable:
                break
            }
        }
        if let active = settings.activeServer, settings.enabled, self.isOurs(active), case let .available(ping) = values[active] {
            let _ = StogramProxy.current.swap(StogramProxy.Status(host: active.host, ping: ping))
        }
        guard let (server, ping) = best else {
            if !stillChecking {
                let _ = StogramProxy.current.swap(StogramProxy.Status(host: settings.activeServer?.host ?? "", ping: nil))
            }
            return
        }
        // Switch only when the current one is off or not working, or another one is clearly faster.
        if settings.enabled, let active = settings.activeServer, case let .available(currentPing) = values[active] {
            if active == server || currentPing <= ping * 1.5 {
                return
            }
        } else if stillChecking && settings.enabled && settings.activeServer != nil {
            return
        }
        let _ = StogramProxy.current.swap(StogramProxy.Status(host: server.host, ping: ping))
        StogramProxy.markManaged(server)
        let _ = updateProxySettingsInteractively(accountManager: self.context.sharedContext.accountManager, { settings in
            var settings = settings
            // Only the chosen one is visible in the proxy list; earlier picks of ours are cleaned up.
            settings.servers.removeAll(where: { $0 != server && StogramProxy.isManaged($0) })
            if !settings.servers.contains(server) {
                settings.servers.insert(server, at: 0)
            }
            settings.activeServer = server
            settings.enabled = true
            return settings
        }).start()
    }
}
