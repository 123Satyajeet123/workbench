// Sends the open Gmail thread to Workbench, only while the person has it open inside the label they named in Workbench.
// It listens and reads; it never clicks, types, focuses or changes the page. The host checks the consent again. When the
// page lost the attributes the reader expects, it sends nothing but one report that the reader is stale.
(() => {
  const { readThread, fetchDeck, splitIntoChunks } = globalThis.WorkbenchMail;
  const settleMilliseconds = 1500;
  const handled = new Set();
  let timer;
  let sending = false;
  let reportedStale = null;

  const ask = (message) => chrome.runtime.sendMessage({ mail: message }).catch(() => undefined);

  function report(site, stale) {
    if (reportedStale === stale) return;
    reportedStale = stale;
    chrome.runtime.sendMessage({ adapter: { site, stale } }).catch(() => undefined);
  }

  async function sendDecks(message, context, wanted) {
    for (const attachment of message.attachments.filter(({ name }) => wanted.includes(name))) {
      const bytes = await fetchDeck(attachment.url);
      if (!bytes) continue;
      const pieces = splitIntoChunks(bytes);
      for (const [index, data] of pieces.entries()) {
        await ask({ type: "mail_deck", context, name: attachment.name, index, count: pieces.length, data });
      }
    }
  }

  async function sendMessage(thread, message) {
    const context = { url: location.href, label: thread.label, threadId: thread.threadId, messageId: message.messageId };
    const reply = await ask({
      type: "mail", context, sender: message.sender, subject: thread.subject, sent: message.sent, text: message.text,
      attachments: message.attachments.map(({ name }) => name),
    });
    if (reply?.error) return;
    await sendDecks(message, context, reply?.wantDecks ?? []);
    handled.add(message.messageId);
  }

  async function sendOpenThread() {
    if (sending || document.visibilityState !== "visible") return;
    const thread = readThread(document, location);
    if (!thread) return;
    if (thread.stale) {
      report(thread.stale, true);
      return;
    }
    report(thread.site, false);
    sending = true;
    try {
      const status = await ask({ type: "mail_status" });
      if (!status?.labels?.includes(thread.label)) return;
      for (const message of thread.messages.filter(({ messageId }) => !handled.has(messageId))) {
        await sendMessage(thread, message);
      }
    } finally {
      sending = false;
    }
  }

  function sendSoon() {
    clearTimeout(timer);
    timer = setTimeout(sendOpenThread, settleMilliseconds);
  }

  window.addEventListener("hashchange", sendSoon);
  new MutationObserver(sendSoon).observe(document.body, { childList: true, subtree: true });
  sendSoon();
})();
