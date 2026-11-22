// Reads only rendered text in the open conversation: the messages the page has loaded, as `data-id` and text. It never
// clicks, scrolls or types. The selectors, the id shape and the deleted-message marker are covered by synthetic
// fixtures and are UNVERIFIED against a live WhatsApp Web tab; check them there before relying on this reader.
(() => {
  const messageKey = /^(?:true|false)_([0-9]+(?:-[0-9]+)?@(?:c\.us|s\.whatsapp\.net|g\.us|lid))_[A-Za-z0-9-]+(?:_[0-9]+(?::[0-9]+)?@(?:c\.us|s\.whatsapp\.net|lid))?$/;
  const bodySelector = ".copyable-text .selectable-text";
  const deletedSelector = '[data-icon="recalled"]';
  const maxMessages = 200;
  const maxCharacters = 20_000;

  const isVisible = (element) => element.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true });

  // The bracket part of the page's own stamp, such as "3:45 PM, 11/22/2026"; null when the page gives none.
  const sentStamp = (body) =>
    /^\[([^\]]+)\]/.exec(body.closest(".copyable-text")?.getAttribute("data-pre-plain-text") ?? "")?.[1] ?? null;

  // A message the page shows as deleted has no text body and carries the deleted marker.
  function messageRows(pane) {
    const rows = new Set(
      [...pane.querySelectorAll(`${bodySelector}, ${deletedSelector}`)].map((part) => part.closest("[data-id]")),
    );
    return [...rows].flatMap((row) => {
      if (!row || !isVisible(row)) return [];
      const body = row.querySelector(bodySelector);
      const deleted = !body && row.querySelector(deletedSelector) !== null;
      if (!body && !deleted) return [];
      const id = row.getAttribute("data-id");
      return [{ id, body, deleted, chatId: messageKey.exec(id)?.[1] }];
    });
  }

  function readOpenChat(doc) {
    const pane = doc.querySelector("#main");
    if (!pane) return { status: "no-open-chat" };

    const rows = messageRows(pane);
    const chatIds = new Set(rows.map((row) => row.chatId));
    if (chatIds.size !== 1 || rows.some((row) => !row.chatId)) return { status: "unverified-chat" };

    const messages = new Map();
    let usedCharacters = 0;
    let truncated = false;
    // Walk newest first so a large loaded history leaves the most recent messages available.
    for (const { id, body, deleted } of rows.reverse()) {
      if (messages.has(id)) continue;
      const text = deleted ? "" : body.innerText.trim();
      if (!deleted && !text) continue;
      if (messages.size >= maxMessages || usedCharacters + text.length > maxCharacters) {
        truncated = true;
        break;
      }
      messages.set(id, deleted ? { id, deleted: true, sent: null } : { id, text, sent: sentStamp(body) });
      usedCharacters += text.length;
    }
    return { status: "read", chatId: [...chatIds][0], truncated, messages: [...messages.values()].reverse() };
  }

  // The store names a chat with "@s.whatsapp.net" where the page writes "@c.us".
  const canonicalChatId = (chatId) => chatId.replace(/@c\.us$/, "@s.whatsapp.net");

  globalThis.WorkbenchWhatsApp = { readOpenChat, canonicalChatId };
})();
