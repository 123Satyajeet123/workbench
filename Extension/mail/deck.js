// Fetches one PDF attachment of the open thread with the person's own Gmail session, and cuts it into chunks for the
// native host. This is the only network request the extension makes: same origin as the page, only the attachment's
// own address, a hard size limit and a cap per hour. A redirect to another origin is an error, not followed.
(() => {
  const chunkSize = 512 * 1024;
  const maximumChunks = 64;
  const maximumDeckBytes = chunkSize * maximumChunks;
  const maximumFetchesPerHour = 20;
  const fetchTimes = [];

  function allowFetch(now) {
    while (fetchTimes.length && now - fetchTimes[0] > 3600_000) fetchTimes.shift();
    if (fetchTimes.length >= maximumFetchesPerHour) return false;
    fetchTimes.push(now);
    return true;
  }

  function sameOrigin(address, pageOrigin) {
    try {
      if (!address) return false;
      const target = new URL(address, pageOrigin);
      return target.protocol === "https:" && target.origin === pageOrigin;
    } catch {
      return false;
    }
  }

  // The PDF's bytes, or null: not the page's origin, over the hourly cap, too large, not a PDF, or a failed request.
  async function fetchDeck(address, pageOrigin = location.origin, now = Date.now()) {
    if (!sameOrigin(address, pageOrigin) || !allowFetch(now)) return null;
    try {
      const response = await fetch(new URL(address, pageOrigin), { credentials: "same-origin", redirect: "error" });
      if (!response.ok || Number(response.headers.get("content-length")) > maximumDeckBytes) return null;
      const bytes = new Uint8Array(await response.arrayBuffer());
      const isPdf = bytes.length > 4 && String.fromCharCode(...bytes.subarray(0, 5)) === "%PDF-";
      return isPdf && bytes.length <= maximumDeckBytes ? bytes : null;
    } catch {
      return null;
    }
  }

  function toBase64(bytes) {
    let binary = "";
    for (let start = 0; start < bytes.length; start += 0x8000) {
      binary += String.fromCharCode(...bytes.subarray(start, start + 0x8000));
    }
    return btoa(binary);
  }

  // The base64 pieces of the bytes, each at most `size` bytes before encoding.
  function splitIntoChunks(bytes, size = chunkSize) {
    const pieces = [];
    for (let start = 0; start < bytes.length; start += size) {
      pieces.push(toBase64(bytes.subarray(start, start + size)));
    }
    return pieces;
  }

  Object.assign(globalThis.WorkbenchMail, { fetchDeck, splitIntoChunks, sameOrigin, chunkSize });
})();
