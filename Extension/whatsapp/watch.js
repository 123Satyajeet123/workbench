// Sends the messages of the open WhatsApp Web chat to Workbench, only while that chat is one the person allowed in
// Workbench, and tells Workbench which chat is open, only while the person has the chooser open. It listens and reads;
// it never clicks, types, focuses or changes the page. The app checks the consent again when it writes, and writes
// nothing while it reads the chat from the Mac's own WhatsApp store.
(() => {
  const { readOpenChat, readChatIdentity, canonicalChatId } = globalThis.WorkbenchWhatsApp;
  const settleMilliseconds = 2000;
  const askMilliseconds = 5000;
  const sentByChat = new Map();
  let offered = null;
  let timer = null;

  const ask = (message) => chrome.runtime.sendMessage({ whatsapp: message });

  async function sendOpenChat() {
    timer = null;
    if (document.visibilityState !== "visible") return;
    const reading = readOpenChat(document);
    if (reading.status !== "read" || reading.messages.length === 0) return;
    const digest = JSON.stringify([reading.messages, reading.members]);
    if (sentByChat.get(reading.chatId) === digest) return;
    const status = await ask({ type: "whatsapp_status" });
    if (!status?.chats?.includes(canonicalChatId(reading.chatId))) return;
    const reply = await ask({ type: "whatsapp_web", messages: reading.messages, members: reading.members });
    if (!reply?.error) sentByChat.set(reading.chatId, digest);
  }

  // The chat that is open, as an id, a kind and a title, and only when Workbench asks for it. A chat that was already
  // open when the chooser opened is found by the slow timer.
  async function offerOpenChat() {
    if (document.visibilityState !== "visible") return;
    const identity = readChatIdentity(document);
    if (identity.status !== "read") return;
    const status = await ask({ type: "whatsapp_status" });
    if (!status?.discover) {
      offered = null;
      return;
    }
    const digest = JSON.stringify(identity);
    if (offered === digest) return;
    const reply = await ask({
      type: "whatsapp_chat_seen",
      chat: identity.chatId,
      title: identity.title,
      members: identity.members,
    });
    if (!reply?.error) offered = digest;
  }

  // At most one reading in a settle period, however busy the page is.
  function sendSoon() {
    timer ??= setTimeout(sendOpenChat, settleMilliseconds);
  }

  new MutationObserver(sendSoon).observe(document.body, { childList: true, subtree: true });
  setInterval(offerOpenChat, askMilliseconds);
  sendSoon();
})();
