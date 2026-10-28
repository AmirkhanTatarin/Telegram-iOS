import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import UndoUI
import PromptUI
import PresentationDataUtils
import TextFormat
import SGSimpleSettings

// Stogram: quick reply templates, private notes about people, "send when online".
extension ChatControllerImpl {
    private func stogramSetInputText(_ text: String) {
        self.updateChatPresentationInterfaceState(animated: true, interactive: true, { state in
            return state.updatedInterfaceState { interfaceState in
                return interfaceState.withUpdatedEffectiveInputState(ChatTextInputState(inputText: NSAttributedString(string: text)))
            }
        })
        self.chatDisplayNode.ensureInputViewFocused()
    }

    private func stogramToast(_ text: String, title: String? = nil) {
        self.present(UndoOverlayController(presentationData: self.presentationData, content: .info(title: title, text: text, timeout: 4.0, customUndoText: nil), elevatedLayout: false, position: .top, animateInAsReplacement: false, action: { _ in return false }), in: .current)
    }

    func stogramPresentTemplates() {
        let presentationData = self.presentationData
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        let templates = SGSimpleSettings.shared.stogramTemplates
        if templates.isEmpty {
            items.append(ActionSheetTextItem(title: "Шаблонов пока нет. Добавьте первый."))
        }
        for template in templates {
            items.append(ActionSheetButtonItem(title: template, color: .accent, action: { [weak self, weak actionSheet] in
                actionSheet?.dismissAnimated()
                self?.stogramSetInputText(template)
            }))
        }
        items.append(ActionSheetButtonItem(title: "Добавить шаблон", color: .accent, font: .bold, action: { [weak self, weak actionSheet] in
            actionSheet?.dismissAnimated()
            self?.stogramAddTemplate()
        }))
        if !templates.isEmpty {
            items.append(ActionSheetButtonItem(title: "Удалить шаблон", color: .destructive, action: { [weak self, weak actionSheet] in
                actionSheet?.dismissAnimated()
                self?.stogramDeleteTemplate()
            }))
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        self.present(actionSheet, in: .window(.root))
    }

    private func stogramAddTemplate() {
        let current = self.presentationInterfaceState.interfaceState.effectiveInputState.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let controller = promptController(context: self.context, text: "Новый шаблон", subtitle: "Текст, который будет вставляться в поле ввода в одно касание.", value: current.isEmpty ? nil : current, placeholder: "Текст шаблона", characterLimit: 1000, apply: { [weak self] value in
            let text = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return
            }
            var templates = SGSimpleSettings.shared.stogramTemplates
            templates.removeAll(where: { $0 == text })
            templates.insert(text, at: 0)
            SGSimpleSettings.shared.stogramTemplates = Array(templates.prefix(30))
            self?.stogramToast("Шаблон сохранён")
        })
        self.present(controller, in: .window(.root))
    }

    private func stogramDeleteTemplate() {
        let presentationData = self.presentationData
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Какой шаблон удалить?")]
        for template in SGSimpleSettings.shared.stogramTemplates {
            items.append(ActionSheetButtonItem(title: template, color: .destructive, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                SGSimpleSettings.shared.stogramTemplates.removeAll(where: { $0 == template })
            }))
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        self.present(actionSheet, in: .window(.root))
    }

    func stogramEditNote(peerId: EnginePeer.Id) {
        let key = "\(peerId.toInt64())"
        let controller = promptController(context: self.context, text: "Заметка о человеке", subtitle: "Видите только вы. Показывается при открытии чата. Пустое поле удаляет заметку.", value: SGSimpleSettings.shared.stogramPeerNotes[key], placeholder: "Например: должен 500 ₽", characterLimit: 500, apply: { [weak self] value in
            let text = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                let _ = SGSimpleSettings.shared.stogramPeerNotes.removeValue(forKey: key)
                self?.stogramToast("Заметка удалена")
            } else {
                SGSimpleSettings.shared.stogramPeerNotes.set(value: text, forKey: key)
                self?.stogramToast(text, title: "📝 Заметка сохранена")
            }
        })
        self.present(controller, in: .window(.root))
    }

    /// Called when the chat opens: shows the note about the person, if there is one.
    func stogramShowNoteIfNeeded() {
        guard let peerId = self.chatLocation.peerId, self.chatLocation.threadId == nil, let note = SGSimpleSettings.shared.stogramPeerNotes["\(peerId.toInt64())"], !note.isEmpty else {
            return
        }
        self.stogramToast(note, title: "📝 Заметка")
    }

    func stogramSendWhenOnline(peerId: EnginePeer.Id) {
        if NovaSendWhenOnline.pendingText(peerId: peerId) != nil {
            NovaSendWhenOnline.cancel(peerId: peerId)
            self.stogramToast("Отложенное сообщение отменено")
            return
        }
        let text = self.presentationInterfaceState.interfaceState.effectiveInputState.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            self.stogramToast("Сначала наберите сообщение в поле ввода, потом выберите этот пункт.")
            return
        }
        NovaSendWhenOnline.schedule(text: text, peerId: peerId)
        self.stogramSetInputText("")
        self.view.endEditing(true)
        self.stogramToast("Сообщение уйдёт, как только человек появится в сети. Stogram должен быть открыт или недавно свёрнут.", title: "⏳ Отправлю, когда будет в сети")
    }
}
