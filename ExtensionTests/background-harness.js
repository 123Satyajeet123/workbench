// Runs the service worker's modules in a headless browser with fake browser parts, and writes what they did as base64
// JSON into the data-background attribute of <html>, for ExtensionBackgroundTests to compare.
import { createDriver } from "../Extension/background/driver.js";
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
  ports[0].reply({ id: 2, kept: false });
  ports[0].reply({ id: 1, kept: true });
  const hostOut = { connects: ports.length, sent: [...ports[0].sent], answers: [await first, await second] };

  const pending = host.ask({ n: 3 });
  now = 10;
  ports[0].close();
  hostOut.whenTheHostDies = await pending;
  hostOut.askDuringTheWait = await host.ask({ n: 4 });
  hostOut.connectsDuringTheWait = ports.length;
  now = 2000;
  const again = host.ask({ n: 5 });
  ports[1].reply({ id: ports[1].sent[0].id, kept: true });
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

{
  const port = fakePort();
  let finishSlowCommand;
  const host = createHost({
    connect: () => port,
    now: () => 0,
    retryAfter: 1000,
    onCommand: (command) =>
      command.command === "slow" ? new Promise((resolve) => (finishSlowCommand = resolve)) : Promise.resolve({ ok: true, echoed: command.command }),
  });
  host.ensureOpen();
  port.reply({ type: "command", id: 41, command: "slow" });
  port.reply({ type: "command", id: 42, command: "quick" });
  const page = host.ask({ url: "https://a.example/" });
  port.reply({ id: port.sent.find((message) => message.url).id, kept: true });
  const pageAnswer = await settled(page);
  const quickResult = port.sent.find((message) => message.id === 42) ?? null;
  const beforeSlowEnds = port.sent.filter((message) => message.type === "command_result").map((message) => message.id);
  finishSlowCommand({ ok: true });
  await settled(new Promise((resolve) => setTimeout(resolve, 10)));
  const afterSlowEnds = port.sent.filter((message) => message.type === "command_result").map((message) => message.id);
  out.commands = { pageAnswer, quickResult, beforeSlowEnds, afterSlowEnds };

  const countedAnswers = [];
  const waiting = [1, 2].map((n) => host.ask({ n }).then((answer) => countedAnswers.push([n, answer])));
  port.reply({ type: "app_unavailable" });
  await Promise.all(waiting);
  const ids = port.sent.filter((message) => message.n).map((message) => message.id);
  ids.forEach((id) => port.reply({ id, kept: true }));
  await settled(new Promise((resolve) => setTimeout(resolve, 10)));
  const next = host.ask({ n: 3 });
  port.reply({ id: port.sent.find((message) => message.n === 3).id, kept: true });
  out.appGone = { answers: countedAnswers, next: await next };
}

{
  const fresh = () => {
    const created = [];
    const removed = [];
    const grouped = [];
    const listeners = [];
    const session = {};
    let nextTab = 100;
    const env = {
      created, removed, grouped, groupUpdates: [], session, listeners, loads: true, incognito: false, unreadable: false, staleGroup: false,
      capFires: false,
    };
    env.tabs = {
      create: async ({ url, active }) => {
        const tab = { id: ++nextTab, url, active, incognito: env.incognito, status: "loading" };
        created.push({ id: tab.id, url, active });
        if (env.loads) setTimeout(() => listeners.forEach((listener) => listener(tab.id, { status: "complete" })), 0);
        return tab;
      },
      get: async () => ({ status: "loading" }),
      remove: async (id) => {
        removed.push(id);
      },
      group: async (options) => {
        grouped.push(options);
        if (env.staleGroup && options.groupId !== undefined) throw new Error("no such group");
        return options.groupId ?? 7;
      },
      sendMessage: async (id, message) => {
        if (env.unreadable) throw new Error("Receiving end does not exist");
        return { title: "T" + id, text: "text of " + id + " " + message.driver };
      },
      onUpdated: {
        addListener: (listener) => listeners.push(listener),
        removeListener: (listener) => listeners.splice(listeners.indexOf(listener), 1),
      },
    };
    env.tabGroups = { update: async (id, options) => env.groupUpdates.push([id, options]) };
    env.storage = {
      get: async (key) => ({ [key]: session[key] }),
      set: async (values) => Object.assign(session, values),
    };
    env.delay = (milliseconds) => (milliseconds === 999 ? (env.capFires ? Promise.resolve() : new Promise(() => {})) : Promise.resolve());
    env.driver = () =>
      createDriver({ tabs: env.tabs, tabGroups: env.tabGroups, storage: env.storage, delay: env.delay, settleMilliseconds: 1, capMilliseconds: 999 });
    return env;
  };
  const open = (driver, url) => driver.handle({ type: "command", id: 1, command: "open", url });

  const main = fresh();
  const driver = main.driver();
  const opened = await open(driver, "https://a.example/");
  const read = await driver.handle({ command: "read", tab: opened.tab });
  const strangerRead = await driver.handle({ command: "read", tab: 5 });
  const unknown = await driver.handle({ command: "click" });
  const second = await open(driver, "https://b.example/");
  const storedBeforeClose = [...main.session.driverTabs];
  const closed = await driver.handle({ command: "close_all" });
  out.driver = {
    opened, read, strangerRead, unknown, second, closed, storedBeforeClose, storedAfterClose: main.session.driverTabs,
    created: main.created, removed: main.removed, grouped: main.grouped, groupUpdates: main.groupUpdates,
  };

  const slow = fresh();
  slow.loads = false;
  slow.capFires = true;
  const timedOut = await open(slow.driver(), "https://slow.example/");
  out.driverTimeout = { timedOut, removed: slow.removed, stored: slow.session.driverTabs, listeners: slow.listeners.length };

  const privateWindow = fresh();
  privateWindow.incognito = true;
  const inPrivate = await open(privateWindow.driver(), "https://p.example/");
  out.driverIncognito = { inPrivate, removed: privateWindow.removed, stored: privateWindow.session.driverTabs };

  const broken = fresh();
  broken.unreadable = true;
  const brokenDriver = broken.driver();
  const brokenTab = await open(brokenDriver, "https://x.example/");
  out.driverUnreadable = await brokenDriver.handle({ command: "read", tab: brokenTab.tab });

  const crashed = fresh();
  const beforeCrash = crashed.driver();
  await open(beforeCrash, "https://c.example/");
  const idsAtCrash = [...crashed.session.driverTabs];
  const afterRestart = crashed.driver();
  await afterRestart.closeAll();
  out.driverRestart = { idsAtCrash, removed: crashed.removed, stored: crashed.session.driverTabs };

  const stale = fresh();
  stale.staleGroup = true;
  const staleDriver = stale.driver();
  await open(staleDriver, "https://s1.example/");
  await open(staleDriver, "https://s2.example/");
  out.driverStaleGroup = { grouped: stale.grouped };
}

document.documentElement.setAttribute("data-background", btoa(unescape(encodeURIComponent(JSON.stringify(out)))));
