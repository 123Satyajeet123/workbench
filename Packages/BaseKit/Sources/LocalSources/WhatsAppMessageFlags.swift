import Foundation

/// What `ZWAMESSAGE.ZFLAGS` says about a message. A forwarded message has bit 7 (0x80) and bit 8 (0x100) set. Bit 9
/// (0x200) marks a channel post; with all three set the app shows no forward mark. Two independent readers agree:
/// IPED `ExtractorIOS.java` lines 767-772 and whatsapp-conversation-exporter `core.py` line 330 (research
/// sources/2026-11-23 sources hardening, part 2).
enum WhatsAppMessageFlags {
    static let forwardingBit: Int64 = 0x80
    static let standardForwardBit: Int64 = 0x100
    static let channelBit: Int64 = 0x200

    static func isForwarded(_ flags: Int64) -> Bool {
        flags & forwardingBit != 0 && flags & standardForwardBit != 0 && flags & channelBit == 0
    }
}
