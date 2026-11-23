// Reads the open Gmail thread from the page: pure functions of the document and the address. They only read; they
// never click, type, focus or change anything. Where the page's ids and facts sit is named in the adapter record
// (read/records.js, unverified against live Gmail); nothing here names a class.
(() => {
  const { generic, interpret, records } = globalThis.WorkbenchReader;
  const labelPattern = /^#label\/(.+)\/[A-Za-z0-9_-]+(?:\?.*)?$/;

  // "#label/Deals/FMfcgz" is a thread opened inside the label Deals. Anything else (inbox, search, a label's list with
  // no thread open) is not a thread in a label.
  function labelOf(hash) {
    const found = labelPattern.exec(hash);
    const label = found ? decodeURIComponent(found[1].replace(/\+/g, " ")) : "";
    return label || null;
  }

  function textOf(node) {
    return (node.innerText ?? node.textContent ?? "").replace(/\n{3,}/g, "\n\n").trim();
  }

  function outermost(elements) {
    return elements.filter((element) => !elements.some((other) => other !== element && other.contains(element)));
  }

  function bodyOf(message, fields) {
    return outermost(interpret.withAttribute(message, fields.body)).map(textOf).filter(Boolean).join("\n\n");
  }

  function senderOf(message, fields) {
    const node = interpret.withAttribute(message, fields.sender)[0];
    if (!node) return "";
    const name = node.getAttribute(fields.senderName);
    const email = node.getAttribute(fields.sender);
    return name && name !== email ? `${name} <${email}>` : email;
  }

  function sentOf(message, fields) {
    for (const node of interpret.withAttribute(message, fields.sent)) {
      const title = node.getAttribute(fields.sent);
      const time = /\b\d{4}\b/.test(title) ? Date.parse(title) : NaN;
      if (!Number.isNaN(time)) return Math.floor(time / 1000);
    }
    return null;
  }

  // "application/pdf:Deck.pdf:https://mail.google.com/mail/u/0?ui=2&..." -> the PDF's name and address.
  function pdfAttachments(message, fields) {
    return interpret.withAttribute(message, fields.attachment).flatMap((node) => {
      const [type, name, ...address] = node.getAttribute(fields.attachment).split(":");
      return type === "application/pdf" && name && address.length ? [{ name, url: address.join(":") }] : [];
    });
  }

  // The expanded messages of the thread open at `place` (a URL), `{ stale: site }` when the page lost the attributes
  // the record expects, or null when no thread with an id is open inside a label.
  function readThread(doc, place) {
    const label = labelOf(place.hash);
    const record = interpret.recordFor(records, place.hostname);
    if (!label || !record) return null;
    if (interpret.checkShape(record, doc, place).stale) return { stale: record.site };
    const { container, items } = interpret.read(record, doc, place);
    if (!container) return null;
    const { fields } = record;
    const messages = items.flatMap(({ id, element }) => {
      const text = bodyOf(element, fields);
      return text && id
        ? [{
            messageId: id, sender: senderOf(element, fields), sent: sentOf(element, fields), text,
            attachments: pdfAttachments(element, fields),
          }]
        : [];
    });
    const subject = generic.firstHeadingText(doc.querySelector("[role='main']") ?? doc);
    return { site: record.site, label, threadId: container.value, threadVia: container.via, subject, messages };
  }

  globalThis.WorkbenchMail = globalThis.WorkbenchMail ?? {};
  Object.assign(globalThis.WorkbenchMail, { labelOf, readThread });
})();
