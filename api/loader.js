// VNDT / ZHM loader
// Discord crawler -> rich YouTube-style preview metadata
// Browser -> YouTube
// Script HTTP clients -> Lua source

const YOUTUBE_URL = "https://m.youtube.com/watch?v=dQw4w9WgXcQ";
const THUMBNAIL = "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg";

export default function handler(req, res) {
  if (req.method !== "GET") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const ua = String(req.headers["user-agent"] || "").toLowerCase();

  // Discord needs actual HTML metadata to generate an embed from the loader URL.
  if (ua.includes("discordbot")) {
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    res.setHeader("Cache-Control", "public, max-age=60");
    res.status(200).send(`<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>YouTube</title>
  <meta property="og:type" content="video.other">
  <meta property="og:title" content="YouTube">
  <meta property="og:description" content="Watch on YouTube">
  <meta property="og:url" content="${YOUTUBE_URL}">
  <meta property="og:image" content="${THUMBNAIL}">
  <meta name="twitter:card" content="summary_large_image">
  <meta http-equiv="refresh" content="0;url=${YOUTUBE_URL}">
</head>
<body>
  <a href="${YOUTUBE_URL}">Watch on YouTube</a>
</body>
</html>`);
    return;
  }

  // Normal browsers go straight to YouTube.
  const isBrowser =
    ua.includes("mozilla") ||
    ua.includes("twitterbot") ||
    ua.includes("facebookexternalhit") ||
    ua.includes("telegrambot") ||
    ua.includes("whatsapp") ||
    ua.includes("slackbot");

  if (isBrowser) {
    res.setHeader("Cache-Control", "no-store, max-age=0");
    res.redirect(302, YOUTUBE_URL);
    return;
  }

  const source = process.env.LUA_SOURCE_NEW || process.env.LUA_SOURCE;

  if (!source) {
    res.status(503).send('warn("VNDT loader source is not configured.")');
    return;
  }

  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate");
  res.status(200).send(source);
}
