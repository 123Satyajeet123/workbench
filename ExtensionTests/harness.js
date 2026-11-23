// Runs the extension's reading and deck code in a headless browser against the fixture on the page, and writes what it
// found as base64 JSON into the data-out attribute of <html>, for ExtensionReaderTests to compare. A variant changes the
// fixture, reads it, and puts the fixture back.
(async () => {
  const { generic, interpret, records, page } = globalThis.WorkbenchReader;
  const { labelOf, readThread, sameOrigin, fetchDeck, splitIntoChunks } = globalThis.WorkbenchMail;
  const fixture = document.getElementById("fixture");
  const place = new URL(document.querySelector("meta[name=location]").content);
  const view = { width: innerWidth, height: innerHeight };
  const original = fixture.innerHTML;
  const out = {};

  function variant(change, read) {
    change(fixture);
    try {
      return read();
    } finally {
      fixture.innerHTML = original;
    }
  }
  const without = (...names) => (root) =>
    root.querySelectorAll("*").forEach((element) => names.forEach((name) => element.removeAttribute(name)));
  const readPage = () => page.readPage({ doc: document, location: place, view, records });
  const readMail = () => readThread(document, place);

  out.page = readPage();
  out.pageWithoutClasses = variant(without("class"), readPage);
  out.pageWithoutItemAttributes = variant(
    without("id", "data-message-id", "data-thread-id", "data-legacy-thread-id", "data-legacy-last-message-id"),
    readPage,
  );
  out.blocks = generic.readBlocks(document.body, view);
  out.blocksWithoutAView = generic.readBlocks(document.body, null);

  if (place.hostname === "mail.google.com") {
    const unnamedFirst = (root) => {
      const first = root.querySelector("[data-message-id]");
      first.setAttribute("data-message-id", "x");
      first.removeAttribute("data-legacy-last-message-id");
    };
    out.thread = readMail();
    out.dateInTitle = Math.floor(Date.parse(document.querySelector("[title]").getAttribute("title")) / 1000);
    out.threadWithoutClasses = variant(without("class"), readMail);
    out.threadWithoutQuoteTag = variant(
      (root) =>
        root.querySelectorAll("blockquote").forEach((quote) => {
          const plain = document.createElement("div");
          plain.innerHTML = quote.innerHTML;
          quote.replaceWith(plain);
        }),
      readMail,
    );
    out.threadWithoutAccount = variant(without("aria-label"), readMail);
    out.threadWithoutAddressAttributes = variant(without("email"), readMail);
    out.threadWithoutThreadId = variant(without("data-thread-id"), readMail);
    out.threadFromTheAddress = variant(without("data-thread-id", "data-legacy-thread-id"), readMail);
    out.threadWithoutMessageIds = variant(without("data-message-id"), readMail);
    out.pageWithOneUnnamedMessage = variant(unnamedFirst, readPage);
    out.threadWithOneUnnamedMessage = variant(unnamedFirst, readMail);
    const gmail = records.find((record) => record.hosts.includes(place.hostname));
    const naming = (attribute) => ({ ...gmail, item: { ...gmail.item, with: { attribute } } });
    out.itemsNamedByAttribute = Object.fromEntries(
      ["data-message-id", "class", "[class]", "data-message-id]"].map((attribute) => [
        attribute,
        interpret.read(naming(attribute), document, place).items.length,
      ]),
    );
    out.labels = Object.fromEntries(
      [
        "#label/Deals/FMfcgzQ", "#label/Hot+Deals/FMfcgzQ", "#label/Parent%2FChild/FMfcgzQ",
        "#label/Deals/FMfcgzQ?compose=new", "#inbox", "#label/Deals", "#search/acme/FMfcgzQ", "#label/Deals/not%20an%20id",
        "", "#label//FMfcgzQ",
      ].map((hash) => [hash, labelOf(hash)]),
    );
    out.noThreadOutsideALabel = ["#inbox", "#search/acme/FMfcgzQ", "#label/Deals"].map((hash) =>
      readThread(document, new URL("https://mail.google.com/mail/u/0/" + hash)),
    );
  }

  const inner = document.getElementById("inner");
  if (inner) {
    await new Promise((resolve) => {
      if (inner.contentDocument.body?.textContent.trim()) resolve();
      else inner.addEventListener("load", resolve);
    });
    out.frames = {
      top: generic.readText(document.body, view),
      inner: generic.readText(inner.contentDocument.body, view),
    };
  }

  const origin = "https://mail.google.com";
  out.sameOrigin = Object.fromEntries(
    [
      "https://mail.google.com/mail/u/0?ui=2&view=att", "/mail/u/0?ui=2&view=att", "http://mail.google.com/mail/u/0",
      "https://evil.example/x.pdf", "//evil.example/x.pdf", "https://mail.google.com.evil.example/x.pdf",
      "https://mail-attachment.googleusercontent.com/attachment/u/0/", "javascript:alert(1)", "",
    ].map((address) => [address, sameOrigin(address, origin)]),
  );

  const pdf = new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x37, 0x0a, 1, 2, 3]);
  const calls = [];
  let answer = () => new Response(pdf, { headers: { "content-length": String(pdf.length) } });
  globalThis.fetch = async (address, options) => {
    calls.push({ address: String(address), credentials: options.credentials, redirect: options.redirect });
    return answer();
  };

  const good = await fetchDeck("/mail/u/0?ui=2&view=att", origin, 1000);
  out.fetched = good ? [...good] : null;
  out.fetchOptions = calls[0];
  const before = calls.length;
  out.foreign = [
    await fetchDeck("https://evil.example/x.pdf", origin, 1000),
    await fetchDeck("https://mail.google.com.evil.example/x.pdf", origin, 1000),
    await fetchDeck("http://mail.google.com/x.pdf", origin, 1000),
  ];
  out.callsForForeign = calls.length - before;
  answer = () => new Response(new Uint8Array([1, 2, 3, 4, 5, 6]));
  out.notAPdf = await fetchDeck("/mail/u/0?x=1", origin, 1000);
  answer = () => new Response(pdf, { headers: { "content-length": String(64 * 512 * 1024 + 1) } });
  out.tooBig = await fetchDeck("/mail/u/0?x=2", origin, 1000);
  answer = () => new Response("", { status: 403 });
  out.refused = await fetchDeck("/mail/u/0?x=3", origin, 1000);
  answer = () => { throw new TypeError("redirect"); };
  out.redirected = await fetchDeck("/mail/u/0?x=4", origin, 1000);
  answer = () => new Response(pdf);
  out.rateWithinAnHour = [];
  for (let n = 0; n < 30; n++) out.rateWithinAnHour.push((await fetchDeck("/mail/u/0?n=" + n, origin, 2000)) !== null);
  out.fetchesInTheHour = calls.length;
  out.allowedAfterTheHour = (await fetchDeck("/mail/u/0?late", origin, 1000 + 3601_000)) !== null;

  const bytes = new Uint8Array(1_200_000).map((_, index) => (index * 31) % 251);
  const pieces = splitIntoChunks(bytes);
  const joined = pieces.flatMap((piece) => [...Uint8Array.from(atob(piece), (c) => c.charCodeAt(0))]);
  out.chunkCount = pieces.length;
  out.chunksRoundTrip = joined.length === bytes.length && joined.every((value, index) => value === bytes[index]);
  out.smallestChunk = splitIntoChunks(new Uint8Array(0)).length;

  document.documentElement.setAttribute("data-out", btoa(unescape(encodeURIComponent(JSON.stringify(out)))));
})();
