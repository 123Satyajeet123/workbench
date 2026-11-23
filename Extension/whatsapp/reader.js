// Reads only rendered text in the open conversation: the messages the page has loaded, as `data-id` and text. It never
// clicks, scrolls or types. The selectors, the id shape and the deleted-message marker are covered by synthetic
// fixtures and are UNVERIFIED against a live WhatsApp Web tab; check them there before relying on this reader.
(() => {
  const messageKey = /^(?:true|false)_([0-9]+(?:-[0-9]+)?@(?:c\.us|s\.whatsapp\.net|g\.us|lid))_[A-Za-z0-9-]+(?:_[0-9]+(?::[0-9]+)?@(?:c\.us|s\.whatsapp\.net|lid))?$/;
  const bodySelector = ".copyable-text .selectable-text";
  const deletedSelector = '[data-icon="recalled"]';
  const jidAttribute = /^[0-9]+(?:[-:][0-9]+)?@(?:c\.us|s\.whatsapp\.net|lid)$/;
  // Guesses for the header and the group-info panel. UNVERIFIED: run probe.js on a live tab and correct them.
  const selectors = {
    chatTitle: '#main header span[dir="auto"]',
    panel: '[data-testid="group-info-drawer"]',
    panelTitle: '[role="heading"]',
    participantRow: '[role="listitem"]',
    participantsCount: '[data-testid="participants-count"]',
  };
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

  const chatTitle = (doc) => doc.querySelector(selectors.chatTitle)?.textContent.trim() || null;

  // An id is read only from an attribute whose whole value is an id. Text, such as a name or a shown number, is never
  // turned into an id.
  function idIn(row) {
    for (const element of [row, ...row.querySelectorAll("*")]) {
      for (const attribute of element.attributes) {
        if (jidAttribute.test(attribute.value)) return attribute.value;
      }
    }
    return null;
  }

  // The members of the open group, from the group-info panel the person opened; null while that panel is not open
  // or is not the panel of the open chat. `rows` counts the participants shown and `stated` the count the panel
  // gives, so the app can tell a list that is whole from one that is not.
  function readParticipants(doc) {
    const panel = doc.querySelector(selectors.panel);
    const title = chatTitle(doc);
    if (!panel || !title || panel.querySelector(selectors.panelTitle)?.textContent.trim() !== title) return null;
    const rows = [...panel.querySelectorAll(selectors.participantRow)];
    const stated = /\d+/.exec(panel.querySelector(selectors.participantsCount)?.textContent ?? "");
    return {
      ids: rows.flatMap((row) => idIn(row) ?? []),
      rows: rows.length,
      stated: stated ? Number(stated[0]) : null,
    };
  }

  function openChatRows(doc) {
    const pane = doc.querySelector("#main");
    if (!pane) return { status: "no-open-chat" };
    const rows = messageRows(pane);
    const chatIds = new Set(rows.map((row) => row.chatId));
    if (chatIds.size !== 1 || rows.some((row) => !row.chatId)) return { status: "unverified-chat" };
    return { rows, chatId: [...chatIds][0] };
  }

  // Which chat is open and what it is called, for the chooser. It carries no message.
  function readChatIdentity(doc) {
    const { status, chatId } = openChatRows(doc);
    const title = chatTitle(doc);
    if (!chatId || !title) return { status: status ?? "no-title" };
    return { status: "read", chatId, title, members: chatId.endsWith("@g.us") ? readParticipants(doc) : null };
  }

  function readOpenChat(doc) {
    const { status, rows, chatId } = openChatRows(doc);
    if (!rows) return { status };

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
    return {
      status: "read",
      chatId,
      truncated,
      messages: [...messages.values()].reverse(),
      members: chatId.endsWith("@g.us") ? readParticipants(doc) : null,
    };
  }

  // The store names a chat with "@s.whatsapp.net" where the page writes "@c.us".
  const canonicalChatId = (chatId) => chatId.replace(/@c\.us$/, "@s.whatsapp.net");

  globalThis.WorkbenchWhatsApp = { readOpenChat, readChatIdentity, canonicalChatId };
})();
