import { verifyKey } from "../lib/key.js";

export default function handler(req, res) {
  if (req.method !== "GET") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const key = String(req.query.key || "");
  if (!verifyKey(key)) {
    res.status(401).send('error("Invalid or expired VNDT key")');
    return;
  }

  const source = process.env.LUA_SOURCE_NEW;
  if (!source) {
    res.status(503).send('error("VNDT source is not configured")');
    return;
  }

  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate");
  res.status(200).send(source);
}
