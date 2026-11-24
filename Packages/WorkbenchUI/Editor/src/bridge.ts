import type { ToEditor, ToSwift } from "./bridge.generated.ts";

interface Host {
  webkit?: { messageHandlers: { bridge: { postMessage(message: string): void } } };
  bridge?: { receive(json: string): void };
}

/** The only way out of the page: a typed message to Swift. */
export function send(message: ToSwift): void {
  (window as unknown as Host).webkit?.messageHandlers.bridge.postMessage(JSON.stringify(message));
}

/** The only way in: Swift calls `window.bridge.receive` with one typed message. */
export function listen(handler: (message: ToEditor) => void): void {
  (window as unknown as Host).bridge = { receive: (json) => handler(JSON.parse(json) as ToEditor) };
}

/** Tells Swift each load the Content Security Policy refused. */
export function reportBlockedLoads(): void {
  document.addEventListener("securitypolicyviolation", (event) => {
    send({ type: "blocked", directive: event.effectiveDirective, uri: event.blockedURI });
  });
}
