// VNDT / ZHM loader
// Browser / Discord -> YouTube
// Script HTTP clients -> Lua source

const YOUTUBE_URL = "https://www.youtube.com/watch?v=dQw4w9WgXcQ";

export default function handler(req, res) {
  if (req.method !== "GET") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const ua = String(req.headers["user-agent"] || "").toLowerCase();

  // Normal browsers and common link-preview crawlers get the YouTube page.
  // This creates the YouTube-style preview when the loader URL is shared.
  const isBrowserOrPreview =
    ua.includes("mozilla") ||
    ua.includes("discordbot") ||
    ua.includes("twitterbot") ||
    ua.includes("facebookexternalhit") ||
    ua.includes("telegrambot") ||
    ua.includes("whatsapp") ||
    ua.includes("slackbot");

  if (isBrowserOrPreview) {
    res.setHeader("Cache-Control", "no-store, max-age=0");
    res.redirect(302, YOUTUBE_URL);
    return;
  }

  const source = process.env.LUA_SOURCE;

  if (!source) {
    res.status(503).send('warn("VNDT loader source is not configured.")');
    return;
  }

  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate");
  res.status(200).send(source);
}
