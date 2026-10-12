import { verifyKey } from "../lib/key.js";

const SCRIPT_ENV_BY_ID = {
  "135762233659303": "SCRIPT_TINAPAY",
  "76761322556241": "SCRIPT_UKAYUKAY",
  "76943966208523": "SCRIPT_CLONESTEALEGG",
  "114326934417838": "SCRIPT_BREAK_EGG",
  "109475655864288": "SCRIPT_SUKI",
  "90920025162454": "SCRIPT_ROLLAFISHERMAN"
};

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

  const placeId = String(req.query.placeId || "");
  const gameId = String(req.query.gameId || "");
  const envName = SCRIPT_ENV_BY_ID[placeId] || SCRIPT_ENV_BY_ID[gameId];

  if (!envName) {
    res.status(404).send('error("This game is not supported by VNDT")');
    return;
  }

  const source = process.env[envName];
  if (!source) {
    res.status(503).send('error("Protected script is not configured on the server")');
    return;
  }

  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate");
  res.status(200).send(source);
}
