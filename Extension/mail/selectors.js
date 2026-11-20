// The one place that names Gmail's page structure. UNVERIFIED: these class names and attributes come from research 41
// and the gmail.js source (hP, adn, a3s, gD, g3, aZo), and are checked only against the saved fixtures in
// Extension/test/fixtures, which were written to match them. No live Gmail tab has been read. Gmail changes these
// names without notice; when a read comes back empty, fix them here and in the fixtures.
(() => {
  globalThis.WorkbenchMail = globalThis.WorkbenchMail ?? {};
  globalThis.WorkbenchMail.selectors = Object.freeze({
    subject: "h2.hP",
    // One expanded or collapsed message of the open thread; its data-message-id is "#msg-f:<number>".
    message: "div.adn[data-message-id]",
    // Present only in an expanded message.
    body: "div.a3s",
    // Carries the sender's name and email as attributes.
    sender: "span.gD[email]",
    // Its title attribute holds the full date, such as "Fri, Nov 20, 2026, 3:04 PM".
    date: "span.g3[title]",
    // Its download_url attribute is "<mime type>:<file name>:<address>".
    attachment: "span.aZo[download_url]",
  });
})();
