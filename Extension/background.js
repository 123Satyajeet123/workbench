// Passes each page from a content script to the Workbench native host, which applies the person's capture policy.
const host = "com.hizen.workbench.pages";
const isBrave = (navigator.userAgentData?.brands ?? []).some((entry) => entry.brand === "Brave");
const browser = isBrave ? "com.brave.Browser" : "com.google.Chrome";

chrome.runtime.onMessage.addListener((page, sender) => {
  if (!sender.tab || sender.tab.incognito) return;
  chrome.runtime.sendNativeMessage(host, { browser, url: page.url, title: page.title, text: page.text }, () => {
    void chrome.runtime.lastError;
  });
});
