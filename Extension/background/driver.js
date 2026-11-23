// Opens pages the app names and reads their text, in tabs the person never sees: inactive tabs inside one collapsed
// tab group named "Workbench", in the current window. It only opens, reads and closes. A command comes only from the
// native port (see host.js); a page can never send one. Every tab it opens is closed on `close_all`, when its own
// open fails, and when the service worker starts. The ids of its tabs are kept in session storage for that.
//
// Commands { command, ... } and results { ok, ... }:
//   open       { url }   -> { ok: true, tab }       the tab loaded: status complete, then a short settle
//   read       { tab }   -> { ok: true, title, text }   the whole text of a tab this driver opened
//   close_all            -> { ok: true, closed }
// A failure is { ok: false, error } with one of: timeout, incognito, unknown_tab, unreadable, unknown_command,
// browser_error.
export const groupTitle = "Workbench";
const storedKey = "driverTabs";

class DriverError extends Error {}

const failure = (error) => ({ ok: false, error });

export function createDriver({ tabs, tabGroups, storage, delay, settleMilliseconds, capMilliseconds }) {
  let groupId = null;

  const stored = async () => (await storage.get(storedKey))[storedKey] ?? [];
  const remember = (ids) => storage.set({ [storedKey]: ids });

  function withinCap(work) {
    const expired = delay(capMilliseconds).then(() => {
      throw new DriverError("timeout");
    });
    return Promise.race([work, expired]);
  }

  async function closeTab(id) {
    await tabs.remove(id).catch(() => undefined);
    await remember((await stored()).filter((kept) => kept !== id));
  }

  async function closeAll() {
    const ids = await stored();
    await remember([]);
    groupId = null;
    await Promise.all(ids.map((id) => tabs.remove(id).catch(() => undefined)));
    return { ok: true, closed: ids.length };
  }

  async function collapseIntoGroup(tabId) {
    const tabIds = [tabId];
    groupId = await tabs.group(groupId === null ? { tabIds } : { tabIds, groupId }).catch(() => tabs.group({ tabIds }));
    await tabGroups.update(groupId, { title: groupTitle, collapsed: true });
  }

  function untilComplete(tabId) {
    let onUpdated;
    const complete = new Promise((resolve) => {
      onUpdated = (id, change) => id === tabId && change.status === "complete" && resolve();
      tabs.onUpdated.addListener(onUpdated);
      tabs.get(tabId).then((tab) => onUpdated(tabId, { status: tab.status }));
    });
    return withinCap(complete).finally(() => tabs.onUpdated.removeListener(onUpdated));
  }

  async function open({ url }) {
    const tab = await tabs.create({ url, active: false });
    await remember([...(await stored()), tab.id]);
    try {
      if (tab.incognito) throw new DriverError("incognito");
      await collapseIntoGroup(tab.id);
      await untilComplete(tab.id);
      await delay(settleMilliseconds);
      return { ok: true, tab: tab.id };
    } catch (error) {
      await closeTab(tab.id);
      throw error;
    }
  }

  async function read({ tab }) {
    if (!(await stored()).includes(tab)) throw new DriverError("unknown_tab");
    const reply = await withinCap(tabs.sendMessage(tab, { driver: "read" })).catch((error) => {
      throw error instanceof DriverError ? error : new DriverError("unreadable");
    });
    if (!reply) throw new DriverError("unreadable");
    return { ok: true, title: reply.title, text: reply.text };
  }

  const commands = { open, read, close_all: closeAll };

  async function handle(message) {
    const run = commands[message.command];
    if (!run) return failure("unknown_command");
    try {
      return await run(message);
    } catch (error) {
      return failure(error instanceof DriverError ? error.message : "browser_error");
    }
  }

  return { handle, closeAll };
}
