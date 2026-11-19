// Sends the text the person can see on this page to Workbench, through the extension's service worker. Only text on
// screen, never what is typed in a field; at most once per interval, and only when it changed.
const maximumCharacters = 20000;
const interval = 10000;
const skipped = "input, textarea, select, [contenteditable=''], [contenteditable='true'], script, style, noscript";
let lastText = "";
let lastSentAt = 0;

function isOnScreen(box) {
  return box.width > 0 && box.height > 0 && box.bottom > 0 && box.right > 0 &&
    box.top < window.innerHeight && box.left < window.innerWidth;
}

function visibleText() {
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  const range = document.createRange();
  const parts = [];
  let length = 0;
  while (walker.nextNode() && length < maximumCharacters) {
    const node = walker.currentNode;
    const text = node.textContent.replace(/\s+/g, " ").trim();
    if (!text || !node.parentElement || node.parentElement.closest(skipped)) continue;
    range.selectNodeContents(node);
    if (!isOnScreen(range.getBoundingClientRect())) continue;
    parts.push(text);
    length += text.length + 1;
  }
  return parts.join("\n").slice(0, maximumCharacters);
}

function sendIfChanged() {
  if (document.visibilityState !== "visible" || !document.body) return;
  if (Date.now() - lastSentAt < interval) return;
  const text = visibleText();
  if (!text || text === lastText) return;
  lastText = text;
  lastSentAt = Date.now();
  chrome.runtime.sendMessage({ url: location.href, title: document.title, text });
}

let scrollTimer;
window.addEventListener("scroll", () => {
  clearTimeout(scrollTimer);
  scrollTimer = setTimeout(sendIfChanged, 1500);
}, { passive: true });
document.addEventListener("visibilitychange", sendIfChanged);
setInterval(sendIfChanged, interval);
setTimeout(sendIfChanged, 2000);
