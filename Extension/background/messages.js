// Turns a message from a content script into the message for the native host, or null when nothing may be sent. The
// address of the page and of each frame come from the browser's own record of the sender, never from the page.
//
// The protocol of the one native port (the host answers each message with one { kept, error?, ... } reply, in order):
//   page           { url, frame?, title, text, items: [{ id, via, text }], container: { value, via } | null }
//   mail           { type: "mail" | "mail_status" | "mail_deck", ... }
//   adapter state  { type: "adapter_state", site, stale }
// A message with no sender tab, or from a private window, is not sent. The message names no browser: the app learns it
// from the parent of the host process.
const mailOrigin = "https://mail.google.com";

function tabAddress(sender) {
  return sender.tab.url ?? (sender.frameId === 0 ? sender.url : null);
}

function isMailTab(sender) {
  try {
    return new URL(tabAddress(sender)).origin === mailOrigin;
  } catch {
    return false;
  }
}

function pageMessage({ title, text, items, container }, sender) {
  const url = tabAddress(sender);
  if (!url) return null;
  return { url, ...(sender.frameId !== 0 && { frame: sender.url }), title, text, items, container };
}

function mailMessage(mail, sender) {
  return isMailTab(sender) ? mail : null;
}

export function toHostMessage({ message, sender }) {
  if (!sender.tab || sender.tab.incognito) return null;
  if (message.mail) return mailMessage(message.mail, sender);
  if (message.page) return pageMessage(message.page, sender);
  if (message.adapter) {
    return { type: "adapter_state", site: message.adapter.site, stale: Boolean(message.adapter.stale) };
  }
  return null;
}
