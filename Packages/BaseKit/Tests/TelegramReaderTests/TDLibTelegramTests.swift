@preconcurrency import TDLibKit
import Testing

@testable import TelegramReader

@Suite struct TDLibTelegramTests {
    @Test func aTextIsKeptAndAServiceMessageIsNot() {
        let text = MessageContent.messageText(
            MessageText(linkPreview: nil, linkPreviewOptions: nil, text: FormattedText(entities: [], text: "Ship it")))
        let plain = TDLibTelegram.plain(text)
        #expect(plain?.kind == .text && plain?.text == "Ship it" && plain?.title == nil)
        #expect(TDLibTelegram.plain(.messageContactRegistered) == nil)
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
