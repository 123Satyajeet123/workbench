// Turns a message from a content script into the message for the native host, or null when nothing may be sent. The
// address of the page and of each frame come from the browser's own record of the sender, never from the page.
//
// The protocol of the one native port. Frames are JSON.
//   extension -> host   a message and its id: { id, ...message }. The host answers with { id, kept, error?, ... }, the same
//                       id, in any order. The id is the extension's own counter; a reply with no waiting id is dropped.
//     page           { url, frame?, title, text, items: [{ id, via, text }], container: { value, via } | null }
//     mail           { type: "mail" | "mail_status" | "mail_deck", ... }
//     adapter state  { type: "adapter_state", site, stale }
//   host -> extension   { type: "app_unavailable" }: the app is not running or went away; every waiting message gets an
//                       error answer. No message is kept or queued meanwhile.
//   host -> extension   { type: "command", id, command, ... }: a command from the app. The extension answers with
//                       { type: "command_result", id, ok, ... }, the same id, without holding any page message back.
//                       The commands and their results are listed in driver.js. Only this port carries commands; a
//                       message from a page or a content script never becomes one.
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
