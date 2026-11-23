// Runs the service worker's modules in a headless browser with fake browser parts, and writes what they did as base64
// JSON into the data-background attribute of <html>, for ExtensionBackgroundTests to compare.
import { createHost } from "../Extension/background/host.js";
import { toHostMessage } from "../Extension/background/messages.js";
import { createRereads, rereadOnNavigation } from "../Extension/background/rereads.js";

const out = {};
function fakePort() {
  const listeners = { message: [], disconnect: [] };
  const sent = [];
  return {
    sent,
    postMessage: (message) => sent.push(message),
    onMessage: { addListener: (listener) => listeners.message.push(listener) },
    onDisconnect: { addListener: (listener) => listeners.disconnect.push(listener) },
    reply: (message) => listeners.message.forEach((listener) => listener(message)),
    close: () => listeners.disconnect.forEach((listener) => listener()),
  };
}

async function settled(promise) {
  return Promise.race([promise, new Promise((resolve) => setTimeout(() => resolve("pending"), 50))]);
}

{
  const ports = [];
  let now = 0;
  let failToConnect = false;
  const host = createHost({
    connect: () => {
      if (failToConnect) throw new Error("no host");
      ports.push(fakePort());
      return ports.at(-1);
    },
    now: () => now,
    retryAfter: 1000,
  });
  const first = host.ask({ n: 1 });
  const second = host.ask({ n: 2 });
  ports[0].reply({ kept: true });
  ports[0].reply({ kept: false });
  const hostOut = { connects: ports.length, sent: [...ports[0].sent], answers: [await first, await second] };

  const pending = host.ask({ n: 3 });
  now = 10;
  ports[0].close();
  hostOut.whenTheHostDies = await pending;
  hostOut.askDuringTheWait = await host.ask({ n: 4 });
  hostOut.connectsDuringTheWait = ports.length;
  now = 2000;
  const again = host.ask({ n: 5 });
  ports[1].reply({ kept: true });
  hostOut.afterTheWait = await again;
  hostOut.connectsAfterTheWait = ports.length;

  ports[1].close();
  failToConnect = true;
  now = 9000;
  hostOut.whenNoHostIsInstalled = await host.ask({ n: 6 });
  hostOut.nothingWaitingAfterAFailure = (await settled(host.ask({ n: 7 }))) !== "pending";
  out.host = hostOut;
}

{
  const tab = { id: 7, url: "https://app.example/view", incognito: false };
  const top = { tab, frameId: 0, url: "https://app.example/view" };
  const frame = { tab, frameId: 4, url: "https://widget.example/inside" };
  const page = { page: { title: "T", text: "words", items: [{ id: null, text: "words" }], container: null } };
  const gmailTab = { id: 8, url: "https://mail.google.com/mail/u/0/#label/Deals/FMfcgzQ", incognito: false };
  const mail = { mail: { type: "mail", context: { url: gmailTab.url, label: "Deals" }, text: "hello" } };
  const to = (message, sender) => toHostMessage({ message, sender });
  out.messages = {
    top: to(page, top),
    frame: to(page, frame),
    frameWithoutTabAddress: to(page, { ...frame, tab: { id: 7, incognito: false } }),
    topWithoutTabAddress: to(page, { ...top, tab: { id: 7, incognito: false } }),
    incognito: to(page, { ...top, tab: { ...tab, incognito: true } }),
    noTab: to(page, { frameId: 0, url: top.url }),
    mailFromGmail: to(mail, { tab: gmailTab, frameId: 0, url: gmailTab.url }),
    mailFromAnotherSite: to(mail, top),
    adapter: to({ adapter: { site: "Gmail", stale: true } }, top),
    unknownKind: to({ other: 1 }, top),
  };
}

{
  const posted = [];
  const portFor = (name) => ({ postMessage: (message) => posted.push([name, message]), onDisconnect: { addListener: () => {} } });
  const rereads = createRereads();
  rereads.register(portFor("a"), { tab: { id: 1 }, frameId: 0 });
  rereads.register(portFor("b"), { tab: { id: 1 }, frameId: 2 });
  const listeners = {};
  const event = (name) => ({ addListener: (listener) => (listeners[name] = listener) });
  rereadOnNavigation({ onHistoryStateUpdated: event("history"), onReferenceFragmentUpdated: event("fragment") }, rereads);
  listeners.history({ tabId: 1, frameId: 0 });
  listeners.fragment({ tabId: 1, frameId: 2 });
  listeners.history({ tabId: 9, frameId: 0 });
  const closing = portFor("c");
  let onClose;
  closing.onDisconnect = { addListener: (listener) => (onClose = listener) };
  rereads.register(closing, { tab: { id: 5 }, frameId: 0 });
  onClose();
  listeners.history({ tabId: 5, frameId: 0 });
  out.rereads = posted;
}

document.documentElement.setAttribute("data-background", btoa(unescape(encodeURIComponent(JSON.stringify(out)))));
