// Sends the messages of the open WhatsApp Web chat to Workbench, only while that chat is one the person allowed in
// Workbench. It listens and reads; it never clicks, types, focuses or changes the page. The app checks the consent
// again when it writes, and writes nothing while it reads the chat from the Mac's own WhatsApp store.
(() => {
  const { readOpenChat, canonicalChatId } = globalThis.WorkbenchWhatsApp;
  const settleMilliseconds = 2000;
  const sentByChat = new Map();
  let timer = null;

  const ask = (message) => chrome.runtime.sendMessage({ whatsapp: message });

  async function sendOpenChat() {
    timer = null;
    if (document.visibilityState !== "visible") return;
    const reading = readOpenChat(document);
    if (reading.status !== "read" || reading.messages.length === 0) return;
    const digest = JSON.stringify(reading.messages);
    if (sentByChat.get(reading.chatId) === digest) return;
    const status = await ask({ type: "whatsapp_status" });
    if (!status?.chats?.includes(canonicalChatId(reading.chatId))) return;
    const reply = await ask({ type: "whatsapp_web", messages: reading.messages });
    if (!reply?.error) sentByChat.set(reading.chatId, digest);
  }

  // At most one reading in a settle period, however busy the page is.
  function sendSoon() {
    timer ??= setTimeout(sendOpenChat, settleMilliseconds);
  }

  new MutationObserver(sendSoon).observe(document.body, { childList: true, subtree: true });
  sendSoon();
})();
