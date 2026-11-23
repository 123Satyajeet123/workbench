// Reads the open Gmail thread from the page: pure functions of the document and the address. They only read; they
// never click, type, focus or change anything. Where the page's ids and facts sit is named in the adapter record
// (read/records.js, unverified against live Gmail); nothing here names a class.
(() => {
  const { interpret, records } = globalThis.WorkbenchReader;
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

  // The text of `body` outside its quoted blocks, read from the text nodes. A line break stands for each break and block.
  function textOutside(body, quoteTag) {
    const walker = body.ownerDocument.createTreeWalker(body, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
      acceptNode: (node) =>
        node.nodeType === Node.ELEMENT_NODE && node.matches(quoteTag) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
    });
    const parts = [];
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (node.nodeType === Node.TEXT_NODE) parts.push(node.data);
      else if (node.matches("br, div, p")) parts.push("\n");
    }
    return parts.join("").replace(/[ \t]*\n[ \t]*/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
  }

  // The words of the message body, and apart from them the text its quoted blocks hold. A quoted block is marked by
  // the tag the record names; no class and no word of the text decides it.
  function bodyOf(message, fields) {
    const own = [];
    const quoted = [];
    for (const body of outermost(interpret.withAttribute(message, fields.body))) {
      const blocks = outermost(interpret.withTag(body, fields.quoted));
      quoted.push(...blocks.map(textOf));
      own.push(blocks.length ? textOutside(body, fields.quoted) : textOf(body));
    }
    return { text: own.filter(Boolean).join("\n\n"), quoted: quoted.filter(Boolean).join("\n\n") };
  }

  // The addresses the header shows, in page order: the sender first, then the people it went to. Only attributes are
  // read; an address in the body text is never taken, and a body node's own attributes are left out.
  function addressesOf(message, fields) {
    const bodies = interpret.withAttribute(message, fields.body);
    const shown = interpret
      .withAttribute(message, fields.address)
      .filter((node) => !bodies.some((body) => body.contains(node)))
      .map((node) => node.getAttribute(fields.address).trim())
      .filter(Boolean);
    return [...new Set(shown)];
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

  function peopleOf(message, fields, account) {
    const [sender = "", ...recipients] = addressesOf(message, fields);
    return { sender, recipients, account };
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
    const account = interpret.identify(record.account ?? [], { doc, location: place })?.value ?? null;
    const messages = items.flatMap(({ id, element }) => {
      const { text, quoted } = bodyOf(element, fields);
      return (text || quoted) && id
        ? [{
            messageId: id, ...peopleOf(element, fields, account), sent: sentOf(element, fields), text, quoted,
            attachments: pdfAttachments(element, fields),
          }]
        : [];
    });
    return { site: record.site, label, threadId: container.value, threadVia: container.via, messages };
  }

  globalThis.WorkbenchMail = globalThis.WorkbenchMail ?? {};
  Object.assign(globalThis.WorkbenchMail, { labelOf, readThread });
})();
