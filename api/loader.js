// ZHM loader
// HTML clients (Discord/browser) -> preview page
// Non-HTML clients (Roblox/executors) -> Lua source

const YOUTUBE_URL = "https://m.youtube.com/watch?v=dQw4w9WgXcQ";
const THUMBNAIL = "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg";

function previewHtml() {
  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Rick Astley - Never Gonna Give You Up</title>
  <link rel="canonical" href="${YOUTUBE_URL}">

  <meta property="og:site_name" content="YouTube">
  <meta property="og:type" content="website">
  <meta property="og:title" content="Rick Astley - Never Gonna Give You Up">
  <meta property="og:description" content="Watch on YouTube">
  <meta property="og:url" content="${YOUTUBE_URL}">
  <meta property="og:image" content="${THUMBNAIL}">
  <meta property="og:image:secure_url" content="${THUMBNAIL}">
  <meta property="og:image:width" content="1280">
  <meta property="og:image:height" content="720">

  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="Rick Astley - Never Gonna Give You Up">
  <meta name="twitter:description" content="Watch on YouTube">
  <meta name="twitter:image" content="${THUMBNAIL}">

  <meta name="theme-color" content="#ff0000">
  <meta http-equiv="refresh" content="0;url=${YOUTUBE_URL}">
  <script>window.location.replace(${JSON.stringify(YOUTUBE_URL)});</script>
</head>
<body>
  <a href="${YOUTUBE_URL}">Watch on YouTube</a>
</body>
</html>`;
}

export default function handler(req, res) {
  const ua = String(req.headers["user-agent"] || "").toLowerCase();
  const accept = String(req.headers["accept"] || "").toLowerCase();

  const wantsHtml =
    accept.includes("text/html") ||
    ua.includes("discordbot") ||
    ua.includes("discord") ||
    ua.includes("mozilla") ||
    ua.includes("twitterbot") ||
    ua.includes("facebookexternalhit") ||
    ua.includes("telegrambot") ||
    ua.includes("whatsapp") ||
    ua.includes("slackbot") ||
    ua.includes("embedly") ||
    ua.includes("iframely");

  if (req.method === "HEAD") {
    res.setHeader(
      "Content-Type",
      wantsHtml ? "text/html; charset=utf-8" : "text/plain; charset=utf-8"
    );
    res.setHeader("Cache-Control", "no-store, max-age=0");
    res.status(200).end();
    return;
  }

  if (req.method !== "GET") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  if (wantsHtml) {
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    res.setHeader("Cache-Control", "no-store, max-age=0");
    res.status(200).send(previewHtml());
    return;
  }

  const source = process.env.LUA_SOURCE_NEW;

  if (!source) {
    res.status(503).send('warn("ZHM loader source is not configured.")');
    return;
  }

  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate");
  res.status(200).send(source);
}
