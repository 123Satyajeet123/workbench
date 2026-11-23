@preconcurrency import TDLibKit
import Testing

@testable import TelegramReader

@Suite struct TDLibTelegramTests {
    @Test func aTextIsKeptAndAServiceMessageIsNot() {
        let text = MessageContent.messageText(
            MessageText(linkPreview: nil, linkPreviewOptions: nil, text: FormattedText(entities: [], text: "Ship it")))
        let plain = TDLibTelegram.plain(text)
        #expect(plain?.kind == .text && plain?.text.text == "Ship it" && plain?.title == nil)
        #expect(TDLibTelegram.plain(.messageContactRegistered) == nil)
    }

    @Test func everyChatKeepsLoadingBothListsUntilTelegramSaysTheyAreDone() async throws {
        let batches: [ChatList: [[Int64]]] = [.chatListMain: [[1, 2], [3], [4]], .chatListArchive: [[5], [2]]]
        var loaded: [ChatList: Int] = [:]
        let ids = try await TDLibTelegram.everyChat(
            load: { list in
                let count = loaded[list, default: 0]
                guard count < batches[list, default: []].count else {
                    throw TDLibKit.Error(code: 404, message: "Not Found")
                }
                loaded[list] = count + 1
            },
            list: { list in Array(batches[list, default: []].prefix(loaded[list, default: 0]).joined()) })
        #expect(ids == [1, 2, 3, 4, 5])
        #expect(loaded == [.chatListMain: 3, .chatListArchive: 2])
    }

    @Test func everyChatStopsOnAnyOtherTelegramError() async {
        await #expect(throws: TDLibKit.Error.self) {
            try await TDLibTelegram.everyChat(
                load: { _ in throw TDLibKit.Error(code: 401, message: "Unauthorized") }, list: { _ in [] })
        }
    }

    @Test func aTagOfMeByUsernameOrByNameNamesTheFounder() {
        let text = FormattedText(
            entities: [
                TextEntity(length: 9, offset: 0, type: .textEntityTypeMention),
                TextEntity(
                    length: 4, offset: 13, type: .textEntityTypeMentionName(TextEntityTypeMentionName(userId: 7))),
                TextEntity(length: 7, offset: 22, type: .textEntityTypeMention),
                TextEntity(length: 4, offset: 38, type: .textEntityTypeBold),
            ],
            text: "@Shivansh 👍 Shiv aur @ravi_k approve karo")
        #expect(
            TDLibTelegram.tagged(text, me: 7, usernames: ["shivansh"], as: "Kabir (You)")
                == "@Kabir (You) 👍 @Kabir (You) aur @ravi_k approve karo")
        #expect(TDLibTelegram.tagged(text, me: nil, usernames: [], as: "Kabir (You)") == text.text)
    }

    @Test func telegramErrorsReadAsPlainWords() {
        #expect(
            TDLibTelegram.text(of: TDLibKit.Error(code: 400, message: "API_ID_INVALID"))
                == "Telegram did not accept this API ID and hash. Copy them again from my.telegram.org.")
        #expect(
            TDLibTelegram.text(of: TDLibKit.Error(code: 400, message: "PASSWORD_HASH_INVALID"))
                == "That is not your Telegram password.")
    }
}
