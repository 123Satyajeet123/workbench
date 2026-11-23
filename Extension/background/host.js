// The one native port. Every message carries an id and its reply carries the same id, so a reply belongs to the message
// with that id, in whatever order replies come. The host may send a command at any time; each command is answered
// apart from the messages, so a slow command never holds a page message back. When the app is gone the host sends
// { type: "app_unavailable" } and every waiting message gets an error answer. When the port closes or cannot open,
// every waiting message gets an error answer too, and the next message gets one until `retryAfter` milliseconds have
// passed: the extension then sends nothing.
export const refusal = (reason) => ({ kept: false, error: reason });

const appUnavailable = "app_unavailable";
const commandType = "command";

export function createHost({ connect, now, retryAfter, onCommand = async () => ({ ok: false, error: "no commands" }) }) {
  let port = null;
  let failedAt = null;
  let nextId = 0;
  const waiting = new Map();

  function failAll(reason) {
    const answers = [...waiting.values()];
    waiting.clear();
    answers.forEach((answer) => answer(refusal(reason)));
  }

  function fail(reason) {
    port = null;
    failedAt = now();
    failAll(reason);
  }

  function answerCommand(command) {
    onCommand(command).then((result) => port?.postMessage({ ...result, type: "command_result", id: command.id }));
  }

  function receive(message) {
    if (message.type === appUnavailable) failAll("the app is not running");
    else if (message.type === commandType) answerCommand(message);
    else {
      const answer = waiting.get(message.id);
      waiting.delete(message.id);
      answer?.(message);
    }
  }

  function open() {
    port = connect();
    failedAt = null;
    port.onMessage.addListener(receive);
    port.onDisconnect.addListener(() => fail(globalThis.chrome?.runtime?.lastError?.message ?? "the host closed"));
  }

  function ensureOpen() {
    try {
      if (!port) open();
    } catch (error) {
      fail(String(error));
    }
    return Boolean(port);
  }

  function ask(message) {
    return new Promise((answer) => {
      if (!port && failedAt !== null && now() - failedAt < retryAfter) {
        answer(refusal("the host is not available"));
        return;
      }
      const id = ++nextId;
      try {
        if (!port) open();
        waiting.set(id, answer);
        port.postMessage({ ...message, id });
      } catch (error) {
        waiting.delete(id);
        fail(String(error));
        answer(refusal(String(error)));
      }
    });
  }

  return { ask, ensureOpen };
}
