import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import SGSimpleSettings
import NovaAPI

/// Stogram: антиспам для личных чатов (флаг novaAntiSpam, по умолчанию выключен).
///
/// Первое входящее от незнакомца — не контакт, не бот, не служебный аккаунт, и мы ему ни разу не писали —
/// уходит на сервер (/novagram/spam). Если это спам, чат молча переносится в архив: ничего не удаляем,
/// человек сам найдёт его там. Каждого собеседника проверяем один раз (список хранится на телефоне),
/// поэтому дальнейшие сообщения того же человека на сервер не уходят.
final class NovaAntiSpam {
    private static let checkedKey = "novaAntiSpamChecked"
    private static let checkedLimit = 3000

    private let context: AccountContext
    private let disposable = MetaDisposable()
    private var checked: [Int64]
    private var checkedSet: Set<Int64>

    init(context: AccountContext) {
        self.context = context
        self.checked = (UserDefaults.standard.array(forKey: NovaAntiSpam.checkedKey) as? [NSNumber])?.map { $0.int64Value } ?? []
        self.checkedSet = Set(self.checked)

        self.disposable.set((context.account.stateManager.notificationMessages
        |> deliverOnMainQueue).start(next: { [weak self] messageList in
            self?.handle(messageList.flatMap { $0.0 })
        }))
    }

    deinit {
        self.disposable.dispose()
    }

    private func markChecked(_ ids: [Int64]) {
        for id in ids where !self.checkedSet.contains(id) {
            self.checkedSet.insert(id)
            self.checked.append(id)
        }
        if self.checked.count > NovaAntiSpam.checkedLimit {
            self.checked.removeFirst(self.checked.count - NovaAntiSpam.checkedLimit)
            self.checkedSet = Set(self.checked)
        }
        UserDefaults.standard.set(self.checked.map { NSNumber(value: $0) }, forKey: NovaAntiSpam.checkedKey)
    }

    private func handle(_ messages: [Message]) {
        guard SGSimpleSettings.shared.novaAntiSpam, NovaAPI.isConfigured else {
            return
        }
        let accountPeerId = self.context.account.peerId
        // одно, самое первое сообщение от каждого нового собеседника из этой пачки
        var firstByPeer: [PeerId: Message] = [:]
        for message in messages {
            let peerId = message.id.peerId
            guard peerId.namespace == Namespaces.Peer.CloudUser, peerId != accountPeerId,
                  message.flags.contains(.Incoming), !self.checkedSet.contains(peerId.toInt64()) else {
                continue
            }
            if let existing = firstByPeer[peerId], existing.timestamp <= message.timestamp {
                continue
            }
            firstByPeer[peerId] = message
        }
        if firstByPeer.isEmpty {
            return
        }

        let candidatesSignal = self.context.account.postbox.transaction { transaction -> ([NovaAPI.SpamCandidate], [Int64]) in
            var candidates: [NovaAPI.SpamCandidate] = []
            var skipped: [Int64] = []
            for (peerId, message) in firstByPeer {
                guard let user = transaction.getPeer(peerId) as? TelegramUser else {
                    skipped.append(peerId.toInt64())
                    continue
                }
                if user.botInfo != nil || user.flags.contains(.isSupport) || user.flags.contains(.isVerified) || transaction.isPeerContact(peerId: peerId) {
                    skipped.append(peerId.toInt64())
                    continue
                }
                // уже переписывались — значит, не незнакомец
                var wroteBefore = false
                transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: 30) { item in
                    if !item.flags.contains(.Incoming) {
                        wroteBefore = true
                        return false
                    }
                    return true
                }
                let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if wroteBefore || text.isEmpty {
                    skipped.append(peerId.toInt64())
                    continue
                }
                let name = [user.firstName, user.lastName].compactMap { $0 }.joined(separator: " ")
                let from = name.isEmpty ? (user.username.flatMap { "@" + $0 } ?? "?") : name
                candidates.append(NovaAPI.SpamCandidate(id: peerId.toInt64(), from: from, text: String(text.prefix(1000))))
            }
            return (candidates, skipped)
        }

        let _ = (candidatesSignal |> deliverOnMainQueue).start(next: { [weak self] candidates, skipped in
            guard let self else {
                return
            }
            self.markChecked(skipped)
            if candidates.isEmpty {
                return
            }
            let _ = NovaAPI.checkSpam(candidates, completion: { [weak self] spamIds in
                guard let self, let spamIds else {
                    // сервер не ответил — ничего не трогаем, проверим при следующем сообщении
                    return
                }
                self.markChecked(candidates.map { $0.id })
                let peerIds = candidates.filter { spamIds.contains($0.id) }.map { EnginePeer.Id($0.id) }
                if !peerIds.isEmpty {
                    let _ = self.context.engine.peers.updatePeersGroupIdInteractively(peerIds: peerIds, groupId: .archive).startStandalone()
                }
            })
        })
    }
}
