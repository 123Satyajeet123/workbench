// The one native port. Every read goes over it; the host answers each message in order, so a reply belongs to the oldest
// waiting message. When the port closes or cannot open, every waiting message gets an error answer, and the next
// message gets one too until `retryAfter` milliseconds have passed: the extension then sends nothing.
export const refusal = (reason) => ({ kept: false, error: reason });

export function createHost({ connect, now, retryAfter }) {
  let port = null;
  let failedAt = null;
  let waiting = [];

  function fail(reason) {
    port = null;
    failedAt = now();
    waiting.splice(0).forEach((answer) => answer(refusal(reason)));
  }

  function open() {
    port = connect();
    failedAt = null;
    port.onMessage.addListener((reply) => waiting.shift()?.(reply));
    port.onDisconnect.addListener(() => fail(globalThis.chrome?.runtime?.lastError?.message ?? "the host closed"));
  }

  function ask(message) {
    return new Promise((answer) => {
      if (!port && failedAt !== null && now() - failedAt < retryAfter) {
        answer(refusal("the host is not available"));
        return;
      }
      try {
        if (!port) open();
        waiting.push(answer);
        port.postMessage(message);
      } catch (error) {
        waiting = waiting.filter((waiter) => waiter !== answer);
        fail(String(error));
        answer(refusal(String(error)));
      }
    });
  }

  return { ask };
}
