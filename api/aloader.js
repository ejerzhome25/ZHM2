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

  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  res.setHeader("Cache-Control", "no-store, max-age=0");
  res.status(200).send(source);
}
