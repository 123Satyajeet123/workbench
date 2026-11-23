// Each frame's reader keeps one port open to the service worker. When the browser says a frame changed its address
// without loading a new page, the worker tells that frame's reader to read again.
export function createRereads() {
  const ports = new Map();
  const keyOf = (tabId, frameId) => `${tabId}:${frameId}`;

  return {
    register(port, sender) {
      const key = keyOf(sender.tab.id, sender.frameId);
      ports.set(key, port);
      port.onDisconnect.addListener(() => {
        if (ports.get(key) === port) ports.delete(key);
      });
    },
    ask(tabId, frameId) {
      ports.get(keyOf(tabId, frameId))?.postMessage("reread");
    },
  };
}

export function rereadOnNavigation(webNavigation, rereads) {
  const ask = ({ tabId, frameId }) => rereads.ask(tabId, frameId);
  webNavigation.onHistoryStateUpdated.addListener(ask);
  webNavigation.onReferenceFragmentUpdated.addListener(ask);
}
