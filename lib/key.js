import crypto from "crypto";

const PREFIX = "VNDT";
const DEFAULT_TTL_SECONDS = 24 * 60 * 60;

function secret() {
  const value = String(process.env.KEY_SECRET || "");
  if (value.length < 24) {
    throw new Error("KEY_SECRET is missing or too short");
  }
  return value;
}

function sign(message) {
  return crypto
    .createHmac("sha256", secret())
    .update(message)
    .digest("base64url")
    .slice(0, 24);
}

export function issueKey(ttlSeconds = DEFAULT_TTL_SECONDS) {
  const exp = Math.floor(Date.now() / 1000) + ttlSeconds;
  const expPart = exp.toString(36).toUpperCase();
  const nonce = crypto.randomBytes(9).toString("hex").toUpperCase();
  const message = expPart + "." + nonce;
  const signature = sign(message).toUpperCase();
  return `${PREFIX}-${expPart}-${nonce}-${signature}`;
}

export function verifyKey(key) {
  try {
    const value = String(key || "").trim().toUpperCase();
    const parts = value.split("-");
    if (parts.length !== 4 || parts[0] !== PREFIX) return false;

    const expPart = parts[1];
    const nonce = parts[2];
    const provided = parts[3];

    if (!/^[0-9A-Z]+$/.test(expPart)) return false;
    if (!/^[0-9A-F]{18}$/.test(nonce)) return false;

    const exp = parseInt(expPart, 36);
    if (!Number.isFinite(exp) || exp <= Math.floor(Date.now() / 1000)) return false;

    const expected = sign(expPart + "." + nonce).toUpperCase();
    const a = Buffer.from(provided);
    const b = Buffer.from(expected);
    if (a.length !== b.length) return false;
    return crypto.timingSafeEqual(a, b);
  } catch {
    return false;
  }
}
