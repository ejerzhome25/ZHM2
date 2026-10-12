import { issueKey } from "../lib/key.js";

const LINKVERTISE_VERIFY =
  "https://publisher.linkvertise.com/api/v1/anti_bypassing";

export default async function handler(req, res) {
  if (req.method !== "GET") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const hash = String(req.query.hash || "");
  const token = String(process.env.LINKVERTISE_TOKEN || "");

  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate");

  if (!hash) {
    res.status(400).send(page(
      "Missing Linkvertise verification",
      "Open this page through your Linkvertise target link first."
    ));
    return;
  }

  if (!token) {
    res.status(503).send(page(
      "Server not configured",
      "LINKVERTISE_TOKEN is missing in Vercel."
    ));
    return;
  }

  try {
    const verifyUrl =
      LINKVERTISE_VERIFY +
      "?token=" + encodeURIComponent(token) +
      "&hash=" + encodeURIComponent(hash);

    const response = await fetch(verifyUrl, {
      method: "POST",
      headers: { "Accept": "text/plain" }
    });

    const body = (await response.text()).trim().toUpperCase();

    if (!response.ok || body !== "TRUE") {
      res.status(403).send(page(
        "Verification failed",
        "This Linkvertise verification is invalid, expired, or already used."
      ));
      return;
    }

    const key = issueKey();
    res.status(200).send(page(
      "Your VNDT Key",
      key,
      true
    ));
  } catch {
    res.status(500).send(page(
      "Verification error",
      "Could not verify Linkvertise right now. Please try again."
    ));
  }
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function page(title, message, isKey = false) {
  const safeTitle = escapeHtml(title);
  const safeMessage = escapeHtml(message);

  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${safeTitle}</title>
  <style>
    body{margin:0;background:#090b10;color:#fff;font-family:Arial,sans-serif;display:grid;place-items:center;min-height:100vh}
    .card{width:min(92vw,520px);background:#121722;border:1px solid #2b3445;border-radius:18px;padding:26px;box-shadow:0 20px 60px #0008}
    h1{margin:0 0 14px;font-size:24px}
    p{color:#b9c3d4;line-height:1.5}
    .key{margin-top:18px;background:#080b11;border:1px solid #303b50;border-radius:12px;padding:16px;font-family:monospace;font-size:16px;word-break:break-all;user-select:all}
    button{margin-top:14px;width:100%;padding:13px;border:0;border-radius:11px;font-weight:700;cursor:pointer}
  </style>
</head>
<body>
  <div class="card">
    <h1>${safeTitle}</h1>
    ${isKey
      ? `<p>Your key is valid for 24 hours.</p><div id="key" class="key">${safeMessage}</div><button onclick="navigator.clipboard.writeText(document.getElementById('key').innerText)">Copy Key</button>`
      : `<p>${safeMessage}</p>`}
  </div>
</body>
</html>`;
}
