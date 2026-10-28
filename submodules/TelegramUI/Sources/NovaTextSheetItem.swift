import Foundation
import UIKit
import AsyncDisplayKit
import Display

/// Stogram: текст в выдвижной панели снизу (сводка чата, ответ ИИ) — заголовок жирным,
/// текст обычного размера и цвета, по левому краю. Стандартный ActionSheetTextItem мелкий,
/// серый и по центру — для длинной сводки не подходит.
final class NovaTextSheetItem: ActionSheetItem {
    let title: String
    let text: String

    init(title: String, text: String) {
        self.title = title
        self.text = text
    }

    func node(theme: ActionSheetControllerTheme) -> ActionSheetItemNode {
        let node = NovaTextSheetItemNode(theme: theme)
        node.setItem(self)
        return node
    }

    func updateNode(_ node: ActionSheetItemNode) {
        guard let node = node as? NovaTextSheetItemNode else {
            return
        }
        node.setItem(self)
        node.requestLayoutUpdate()
    }
}

final class NovaTextSheetItemNode: ActionSheetItemNode {
    private let theme: ActionSheetControllerTheme
    private let titleNode: ImmediateTextNode
    private let textNode: ImmediateTextNode
    private let accessibilityArea: AccessibilityAreaNode

    override init(theme: ActionSheetControllerTheme) {
        self.theme = theme

        self.titleNode = ImmediateTextNode()
        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.maximumNumberOfLines = 1
        self.titleNode.displaysAsynchronously = false
        self.titleNode.isAccessibilityElement = false

        self.textNode = ImmediateTextNode()
        self.textNode.isUserInteractionEnabled = false
        self.textNode.maximumNumberOfLines = 0
        self.textNode.displaysAsynchronously = false
        self.textNode.textAlignment = .natural
        self.textNode.lineSpacing = 0.15
        self.textNode.isAccessibilityElement = false

        self.accessibilityArea = AccessibilityAreaNode()
        self.accessibilityArea.accessibilityTraits = .staticText

        super.init(theme: theme)

        self.addSubnode(self.titleNode)
        self.addSubnode(self.textNode)
        self.addSubnode(self.accessibilityArea)
    }

    func setItem(_ item: NovaTextSheetItem) {
        let size = self.theme.baseFontSize
        self.titleNode.attributedText = NSAttributedString(string: item.title, font: Font.semibold(floor(size * 17.0 / 17.0)), textColor: self.theme.primaryTextColor)
        self.textNode.attributedText = NSAttributedString(string: item.text, font: Font.regular(floor(size * 16.0 / 17.0)), textColor: self.theme.primaryTextColor)
        self.accessibilityArea.accessibilityLabel = item.title + "\n" + item.text
    }

    override func updateLayout(constrainedSize: CGSize, transition: ContainedViewLayoutTransition) -> CGSize {
        let inset: CGFloat = 18.0
        let width = max(1.0, constrainedSize.width - inset * 2.0)
        let titleSize = self.titleNode.updateLayout(CGSize(width: width, height: 100.0))
        let textSize = self.textNode.updateLayout(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        let size = CGSize(width: constrainedSize.width, height: 16.0 + titleSize.height + 10.0 + textSize.height + 18.0)

        self.titleNode.frame = CGRect(origin: CGPoint(x: inset, y: 16.0), size: titleSize)
        self.textNode.frame = CGRect(origin: CGPoint(x: inset, y: 16.0 + titleSize.height + 10.0), size: textSize)
        self.accessibilityArea.frame = CGRect(origin: CGPoint(), size: size)

        self.updateInternalLayout(size, constrainedSize: constrainedSize)
        return size
    }
}
