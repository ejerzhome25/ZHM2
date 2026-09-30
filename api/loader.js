// VNDT / ZHM loader
// Discord/social crawlers -> YouTube-style rich embed metadata
// Browser -> YouTube
// Script HTTP clients -> Lua source

const YOUTUBE_URL = "https://m.youtube.com/watch?v=dQw4w9WgXcQ";
const YOUTUBE_EMBED = "https://www.youtube.com/embed/dQw4w9WgXcQ";
const THUMBNAIL = "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg";

function previewHtml() {
  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Rick Astley - Never Gonna Give You Up</title>

  <meta property="og:site_name" content="YouTube">
  <meta property="og:type" content="video.other">
  <meta property="og:title" content="Rick Astley - Never Gonna Give You Up">
  <meta property="og:description" content="Watch on YouTube">
  <meta property="og:url" content="${YOUTUBE_URL}">
  <meta property="og:image" content="${THUMBNAIL}">
  <meta property="og:image:secure_url" content="${THUMBNAIL}">
  <meta property="og:image:width" content="1280">
  <meta property="og:image:height" content="720">

  <meta property="og:video" content="${YOUTUBE_EMBED}">
  <meta property="og:video:secure_url" content="${YOUTUBE_EMBED}">
  <meta property="og:video:type" content="text/html">
  <meta property="og:video:width" content="1280">
  <meta property="og:video:height" content="720">

  <meta name="twitter:card" content="player">
  <meta name="twitter:title" content="Rick Astley - Never Gonna Give You Up">
  <meta name="twitter:description" content="Watch on YouTube">
  <meta name="twitter:image" content="${THUMBNAIL}">
  <meta name="twitter:player" content="${YOUTUBE_EMBED}">
  <meta name="twitter:player:width" content="1280">
  <meta name="twitter:player:height" content="720">
</head>
<body>
  <a href="${YOUTUBE_URL}">Watch on YouTube</a>
</body>
</html>`;
}

export default function handler(req, res) {
  const ua = String(req.headers["user-agent"] || "").toLowerCase();

  const isPreviewCrawler =
    ua.includes("discordbot") ||
    ua.includes("discord") ||
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
      isPreviewCrawler ? "text/html; charset=utf-8" : "text/plain; charset=utf-8"
    );
    res.setHeader("Cache-Control", isPreviewCrawler ? "public, max-age=60" : "no-store");
    res.status(200).end();
    return;
  }

  if (req.method !== "GET") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  if (isPreviewCrawler) {
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    res.setHeader("Cache-Control", "public, max-age=60, s-maxage=60");
    res.status(200).send(previewHtml());
    return;
  }

  if (ua.includes("mozilla")) {
    res.setHeader("Cache-Control", "no-store, max-age=0");
    res.redirect(302, YOUTUBE_URL);
    return;
  }

  const source = process.env.LUA_SOURCE_NEW;

  if (!source) {
    res.status(503).send('warn("VNDT loader source is not configured.")');
    return;
  }

  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate");
  res.status(200).send(source);
}
