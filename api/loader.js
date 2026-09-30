// VNDT / ZHM hosted loader endpoint
// YouTube: https://www.youtube.com/watch?v=dQw4w9WgXcQ

export default function handler(req, res) {
  if (req.method !== "GET") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const source = process.env.LUA_SOURCE;

  if (!source) {
    res.status(503).send('warn("VNDT loader source is not configured.")');
    return;
  }

  const banner =
    "--[[ VNDT YOUTUBE: https://www.youtube.com/watch?v=dQw4w9WgXcQ ]]\n";

  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate");
  res.setHeader("Pragma", "no-cache");
  res.status(200).send(banner + source);
}
