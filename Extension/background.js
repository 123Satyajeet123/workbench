// Passes what the content scripts read to the Workbench native host, which hands it to the app; the app applies the
// person's capture policy. Everything goes over one open port, which also carries the app's commands to the page driver. The code that decides lives in background/.
import { createDriver } from "./background/driver.js";
import { createHost, refusal } from "./background/host.js";
import { toHostMessage } from "./background/messages.js";
import { createRereads, rereadOnNavigation } from "./background/rereads.js";

const hostName = "com.hizen.workbench.pages";
const retryAfter = 5000;

const driver = createDriver({
  tabs: chrome.tabs,
  tabGroups: chrome.tabGroups,
  storage: chrome.storage.session,
  delay: (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)),
  settleMilliseconds: 1500,
  capMilliseconds: 30000,
});
const host = createHost({
  connect: () => chrome.runtime.connectNative(hostName),
  now: Date.now,
  retryAfter,
  onCommand: driver.handle,
});
const rereads = createRereads();

driver.closeAll();
host.ensureOpen();

rereadOnNavigation(chrome.webNavigation, rereads);

chrome.runtime.onConnect.addListener((port) => {
  const { tab } = port.sender ?? {};
  if (port.name === "reread" && tab && !tab.incognito) rereads.register(port, port.sender);
});

chrome.runtime.onMessage.addListener((message, sender, respond) => {
  const hostMessage = toHostMessage({ message, sender });
  if (!hostMessage) {
    respond(refusal("not sent"));
    return;
  }
  host.ask(hostMessage).then(respond);
  return true;
});
