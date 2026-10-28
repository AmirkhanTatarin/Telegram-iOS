import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import SGSimpleSettings

/// Stogram: "Отправить, когда в сети". The text waits on the phone (one per chat, SGSimpleSettings.stogramSendWhenOnline)
/// and goes out the moment the person appears online. Works while Stogram is open or recently in the background.
final class NovaSendWhenOnline {
    static let changedNotification = Notification.Name("StogramSendWhenOnlineChanged")

    static func schedule(text: String, peerId: EnginePeer.Id) {
        SGSimpleSettings.shared.stogramSendWhenOnline.set(value: text, forKey: "\(peerId.toInt64())")
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    static func cancel(peerId: EnginePeer.Id) {
        let _ = SGSimpleSettings.shared.stogramSendWhenOnline.removeValue(forKey: "\(peerId.toInt64())")
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    static func pendingText(peerId: EnginePeer.Id) -> String? {
        return SGSimpleSettings.shared.stogramSendWhenOnline["\(peerId.toInt64())"]
    }

    private let context: AccountContext
    private let disposable = MetaDisposable()
    private var observer: NSObjectProtocol?

    init(context: AccountContext) {
        self.context = context
        self.observer = NotificationCenter.default.addObserver(forName: NovaSendWhenOnline.changedNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.watch()
        })
        self.watch()
    }

    deinit {
        self.disposable.dispose()
        if let observer = self.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func watch() {
        let peerIds = SGSimpleSettings.shared.stogramSendWhenOnline.keys.compactMap { Int64($0) }.map { EnginePeer.Id($0) }
        guard !peerIds.isEmpty else {
            self.disposable.set(nil)
            return
        }
        self.disposable.set((self.context.engine.data.subscribe(EngineDataMap(peerIds.map { TelegramEngine.EngineData.Item.Peer.Presence(id: $0) }))
        |> deliverOnMainQueue).start(next: { [weak self] presences in
            guard let self else {
                return
            }
            let now = Int32(Date().timeIntervalSince1970)
            for (peerId, presence) in presences {
                guard let presence, case let .present(until) = presence.status, until >= now else {
                    continue
                }
                let key = "\(peerId.toInt64())"
                guard let text = SGSimpleSettings.shared.stogramSendWhenOnline[key], !text.isEmpty else {
                    continue
                }
                let _ = SGSimpleSettings.shared.stogramSendWhenOnline.removeValue(forKey: key)
                let message: EnqueueMessage = .message(text: text, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                let _ = enqueueMessages(account: self.context.account, peerId: peerId, messages: [message]).startStandalone()
            }
        }))
    }
}
