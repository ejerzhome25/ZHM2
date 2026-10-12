import { verifyKey } from "../lib/key.js";

export default function handler(req, res) {
  if (req.method !== "GET") {
    res.status(405).json({ valid: false, message: "Method Not Allowed" });
    return;
  }

  const key = String(req.query.key || "");
  const valid = verifyKey(key);

  res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate");

  if (!valid) {
    res.status(401).json({
      valid: false,
      success: false,
      message: "Invalid or expired key."
    });
    return;
  }

  res.status(200).json({
    valid: true,
    success: true,
    message: "Key verified."
  });
}
