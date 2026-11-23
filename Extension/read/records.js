// Identity adapters: one record for each site that gives its items names. A record is data. The interpreter reads it;
// no code here. The attribute names and patterns come from research 64 and the gmail.js source and are UNVERIFIED
// against live pages.
//
// hosts       the host names the record covers.
// container   where the id of the place (a thread, a channel) comes from: sources tried in order.
// item        `with` finds the item elements; `id` gives each item's id: sources tried in order.
// fields      names of the attributes that hold more facts about an item, for the code that reads that kind of page.
// shape       `appliesTo` says when the page should have items; `expect` lists what the page must then hold.
//
// A source is { attribute, pattern } (an attribute value) or { url: "hash" | "path", pattern }. The text a pattern
// captures is the id; with no capture the whole value is.
(() => {
  const gmail = {
    site: "Gmail",
    hosts: ["mail.google.com"],
    container: [
      { attribute: "data-thread-id", pattern: "^#?(thread-f:\\d+)$" },
      { attribute: "data-legacy-thread-id", pattern: "^([0-9a-f]{8,32})$" },
      { url: "hash", pattern: "/([A-Za-z0-9_-]+)(?:\\?.*)?$" },
    ],
    item: {
      with: { attribute: "data-message-id" },
      id: [
        { attribute: "data-message-id", pattern: "^#?(msg-f:\\d+)$" },
        { attribute: "data-legacy-last-message-id", pattern: "^([0-9a-f]{8,32})$" },
      ],
    },
    fields: { sender: "email", senderName: "name", sent: "title", attachment: "download_url", body: "dir" },
    shape: {
      appliesTo: { url: "hash", pattern: "^#label/.+/[A-Za-z0-9_-]+(?:\\?.*)?$" },
      expect: [{ attribute: "data-message-id", pattern: "^#?msg-f:\\d+$" }],
    },
  };

  const slack = {
    site: "Slack",
    hosts: ["app.slack.com"],
    container: [{ url: "path", pattern: "^/client/([A-Z0-9]+/[A-Z0-9]+)" }],
    item: {
      with: { attribute: "id", pattern: "^message-list_\\d+\\.\\d+$" },
      id: [{ attribute: "id", pattern: "^message-list_(\\d+\\.\\d+)$" }],
    },
    fields: {},
    shape: {
      appliesTo: { url: "path", pattern: "^/client/[A-Z0-9]+/[A-Z0-9]+" },
      expect: [{ attribute: "id", pattern: "^message-list_\\d+\\.\\d+$" }],
    },
  };

  globalThis.WorkbenchReader = globalThis.WorkbenchReader ?? {};
  globalThis.WorkbenchReader.records = Object.freeze([gmail, slack]);
})();
