// Reads the open Gmail thread from the page: pure functions of the document and the address hash. They only read; they
// never click, type, focus or change anything. The names they look for are in selectors.js (unverified against live Gmail).
(() => {
  const { selectors } = globalThis.WorkbenchMail;
  const threadIdPattern = /^[A-Za-z0-9_-]+$/;

  // "#label/Deals/FMfcgz" is the thread FMfcgz opened inside the label Deals. Anything else (inbox, search, a label's
  // list with no thread open) is not a thread in a label.
  function parseHash(hash) {
    const parts = hash.replace(/^#/, "").split("/");
    if (parts[0] !== "label" || parts.length < 3) return null;
    const threadId = parts[parts.length - 1].split("?")[0];
    if (!threadIdPattern.test(threadId)) return null;
    const label = decodeURIComponent(parts.slice(1, -1).join("/").replace(/\+/g, " "));
    return label ? { label, threadId } : null;
  }

  function textOf(node) {
    return (node.innerText ?? node.textContent ?? "").replace(/\n{3,}/g, "\n\n").trim();
  }

  function senderOf(message) {
    const node = message.querySelector(selectors.sender);
    if (!node) return "";
    const name = node.getAttribute("name");
    const email = node.getAttribute("email");
    return name && name !== email ? `${name} <${email}>` : email;
  }

  function sentOf(message) {
    const title = message.querySelector(selectors.date)?.getAttribute("title");
    const time = title ? Date.parse(title) : NaN;
    return Number.isNaN(time) ? null : Math.floor(time / 1000);
  }

  // "application/pdf:Deck.pdf:https://mail.google.com/mail/u/0?ui=2&..." -> the PDF's name and address.
  function pdfAttachments(message) {
    return [...message.querySelectorAll(selectors.attachment)].flatMap((node) => {
      const [type, name, ...address] = node.getAttribute("download_url").split(":");
      return type === "application/pdf" && name && address.length ? [{ name, url: address.join(":") }] : [];
    });
  }

  // The expanded messages of the thread open at `hash`, or null when no thread is open inside a label.
  function readThread(doc, hash) {
    const place = parseHash(hash);
    if (!place) return null;
    const subject = doc.querySelector(selectors.subject)?.textContent.trim() ?? "";
    const messages = [...doc.querySelectorAll(selectors.message)].flatMap((message) => {
      const body = message.querySelector(selectors.body);
      const text = body ? textOf(body) : "";
      const messageId = message.getAttribute("data-message-id").replace(/^#/, "");
      return text && messageId
        ? [{ messageId, sender: senderOf(message), sent: sentOf(message), text, attachments: pdfAttachments(message) }]
        : [];
    });
    return { ...place, subject, messages };
  }

  Object.assign(globalThis.WorkbenchMail, { parseHash, readThread });
})();
