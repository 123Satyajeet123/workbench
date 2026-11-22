// Passes each page, each Gmail thread and each WhatsApp Web chat from a content script to the Workbench native host,
// which hands it to the app; the app applies the person's capture policy. Pages go one message per host process; mail
// and chats go over one open port, because a deck arrives in chunks the host must hold until the last one is in.
const host = "com.hizen.workbench.pages";
const isBrave = (navigator.userAgentData?.brands ?? []).some((entry) => entry.brand === "Brave");
const browser = isBrave ? "com.brave.Browser" : "com.google.Chrome";
const gmailOrigin = "https://mail.google.com";
const whatsAppOrigin = "https://web.whatsapp.com";

let port = null;
let waiting = [];

function openPort() {
  port = chrome.runtime.connectNative(host);
  port.onMessage.addListener((reply) => waiting.shift()?.(reply));
  port.onDisconnect.addListener(() => {
    const reason = chrome.runtime.lastError?.message ?? "the host closed";
    port = null;
    waiting.splice(0).forEach((answer) => answer({ kept: false, error: reason }));
  });
}

// The host answers each message in order, so the next reply belongs to the oldest waiting message.
function askHost(message) {
  return new Promise((answer) => {
    try {
      if (!port) openPort();
      waiting.push(answer);
      port.postMessage(message);
    } catch (error) {
      waiting = waiting.filter((waiter) => waiter !== answer);
      answer({ kept: false, error: String(error) });
    }
  });
}

function fromTab(sender, origin) {
  return Boolean(sender.tab) && !sender.tab.incognito && new URL(sender.tab.url).origin === origin;
}

chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (!sender.tab || sender.tab.incognito) return;
  if (message.mail) {
    if (!fromTab(sender, gmailOrigin)) return;
    const { context, ...rest } = message.mail;
    askHost({ ...rest, ...(context && { context: { ...context, browser } }) }).then(respond);
    return true;
  }
  if (message.whatsapp) {
    if (!fromTab(sender, whatsAppOrigin)) return;
    askHost({ ...message.whatsapp, browser, url: sender.tab.url }).then(respond);
    return true;
  }
  chrome.runtime.sendNativeMessage(host, { browser, url: message.url, title: message.title, text: message.text }, () => {
    void chrome.runtime.lastError;
  });
});
