// Sends the text the person can see in this frame to Workbench, through the extension's service worker. Only text on
// screen, never what is typed in a field; at most once per interval, and only when it changed. Every frame of a page
// runs this on its own; the service worker tags each frame's text with that frame's address. A single-page app that
// changes its address is read again at once.
(() => {
  const { page, records } = globalThis.WorkbenchReader;
  const interval = 10000;
  const settleMilliseconds = 1500;
  const reconnectMilliseconds = 5000;
  let lastKey = "";
  let lastSentAt = 0;
  let reportedShape = null;
  let timer;

  const send = (message) => chrome.runtime.sendMessage(message).catch(() => undefined);

  function reportShape(shape) {
    if (!shape || (reportedShape?.site === shape.site && reportedShape.stale === shape.stale)) return;
    reportedShape = shape;
    send({ adapter: shape });
  }

  function sendIfChanged({ afterNavigation = false } = {}) {
    if (document.visibilityState !== "visible" || !document.body) return;
    if (!afterNavigation && Date.now() - lastSentAt < interval) return;
    const view = { width: window.innerWidth, height: window.innerHeight };
    const reading = page.readPage({ doc: document, location, view, records });
    reportShape(reading.shape);
    const key = JSON.stringify([reading.text, reading.items]);
    if (!reading.text || key === lastKey) return;
    lastKey = key;
    lastSentAt = Date.now();
    send({ page: { title: document.title, text: reading.text, items: reading.items, container: reading.container } });
  }

  function sendSoon(options) {
    clearTimeout(timer);
    timer = setTimeout(() => sendIfChanged(options), settleMilliseconds);
  }

  function listenForRereads() {
    const port = chrome.runtime.connect({ name: "reread" });
    port.onMessage.addListener(() => sendSoon({ afterNavigation: true }));
    port.onDisconnect.addListener(() => setTimeout(listenForRereads, reconnectMilliseconds));
  }

  window.addEventListener("scroll", () => sendSoon(), { passive: true });
  document.addEventListener("visibilitychange", () => sendIfChanged());
  new MutationObserver(() => sendSoon()).observe(document.documentElement, {
    childList: true, subtree: true, characterData: true,
  });
  setInterval(() => sendIfChanged(), interval);
  setTimeout(() => sendIfChanged(), 2000);
  listenForRereads();
})();
