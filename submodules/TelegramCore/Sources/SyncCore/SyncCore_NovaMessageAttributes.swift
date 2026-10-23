import Foundation
import Postbox

/// Novagram: the message was deleted on the server but kept locally.
public class NovaDeletedMessageAttribute: MessageAttribute {
    public let date: Int32

    public init(date: Int32) {
        self.date = date
    }

    required public init(decoder: PostboxDecoder) {
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.date, forKey: "d")
    }
}

/// Novagram: previous versions of an edited message, oldest first.
public class NovaEditHistoryMessageAttribute: MessageAttribute {
    public let dates: [Int32]
    public let texts: [String]

    public init(dates: [Int32], texts: [String]) {
        self.dates = dates
        self.texts = texts
    }

    required public init(decoder: PostboxDecoder) {
        self.dates = decoder.decodeInt32ArrayForKey("d")
        self.texts = decoder.decodeStringArrayForKey("t")
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32Array(self.dates, forKey: "d")
        encoder.encodeStringArray(self.texts, forKey: "t")
    }

    public func appending(date: Int32, text: String) -> NovaEditHistoryMessageAttribute {
        return NovaEditHistoryMessageAttribute(dates: self.dates + [date], texts: self.texts + [text])
    }
}

public extension Message {
    var novaDeletedDate: Int32? {
        for attribute in self.attributes {
            if let attribute = attribute as? NovaDeletedMessageAttribute {
                return attribute.date
            }
        }
        return nil
    }

    var novaEditHistory: NovaEditHistoryMessageAttribute? {
        for attribute in self.attributes {
            if let attribute = attribute as? NovaEditHistoryMessageAttribute {
                return attribute
            }
        }
        return nil
    }
}

/// Marks messages as deleted instead of removing them. Returns ids that could not be kept.
func novaMarkMessagesDeleted(transaction: Transaction, ids: [MessageId]) -> [MessageId] {
    let now = Int32(Date().timeIntervalSince1970)
    var notKept: [MessageId] = []
    for id in ids {
        guard let currentMessage = transaction.getMessage(id) else {
            notKept.append(id)
            continue
        }
        if currentMessage.novaDeletedDate != nil {
            continue
        }
        transaction.updateMessage(id, update: { currentMessage in
            let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
            var attributes = currentMessage.attributes
            attributes.append(NovaDeletedMessageAttribute(date: now))
            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
        })
    }
    return notKept
}
