// Minimal ElevenLabs client for the voiceover. The key is read at runtime from
// ELEVENLABS_API_KEY or promo/.env and is never printed, logged or written anywhere.
// Every synthesis is cached by a hash of its inputs, so re-renders never call the API again.
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const root = path.dirname(path.dirname(new URL(import.meta.url).pathname));
const API = "https://api.elevenlabs.io";
export const CACHE_DIR = path.join(root, "voice/cache");
const USAGE = path.join(CACHE_DIR, "usage.json");

export const loadKey = (): string | null => {
  if (process.env.ELEVENLABS_API_KEY) return process.env.ELEVENLABS_API_KEY.trim();
  const envFile = path.join(root, ".env");
  if (!fs.existsSync(envFile)) return null;
  for (const line of fs.readFileSync(envFile, "utf8").split("\n")) {
    const m = line.match(/^\s*ELEVENLABS_API_KEY\s*=\s*(.*)\s*$/);
    if (m) return m[1].replace(/^["']|["']$/g, "").trim() || null;
  }
  return null;
};

const redact = (s: string, key: string) => (key ? s.split(key).join("[redacted]") : s);

const req = async (key: string, method: string, url: string, body?: unknown) => {
  const res = await fetch(API + url, {
    method,
    headers: { "xi-api-key": key, "content-type": "application/json", accept: body ? "audio/mpeg" : "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`ElevenLabs ${method} ${url.split("?")[0]} failed: ${res.status} ${redact(text.slice(0, 300), key)}`);
  }
  return res;
};

export const listVoices = async (key: string) => (await (await req(key, "GET", "/v1/voices")).json()) as { voices: any[] };
export const listModels = async (key: string) => (await (await req(key, "GET", "/v1/models")).json()) as any[];

export type VoiceSettings = { stability: number; similarity_boost: number; style: number; use_speaker_boost: boolean; speed?: number };

const usage = (): { characters: number; requests: number } =>
  fs.existsSync(USAGE) ? JSON.parse(fs.readFileSync(USAGE, "utf8")) : { characters: 0, requests: 0 };

/** Text to speech, cached. Returns the path of an mp3 file. */
export const tts = async (key: string | null, voiceId: string, modelId: string, text: string, settings: VoiceSettings) => {
  fs.mkdirSync(CACHE_DIR, { recursive: true });
  const id = crypto.createHash("sha256").update(JSON.stringify({ voiceId, modelId, text, settings, f: "mp3_44100_128" })).digest("hex").slice(0, 20);
  const file = path.join(CACHE_DIR, `${id}.mp3`);
  if (fs.existsSync(file)) return { file, cached: true };
  if (!key) throw new Error("not cached and no ElevenLabs key available");
  const res = await req(key, "POST", `/v1/text-to-speech/${voiceId}?output_format=mp3_44100_128`, { text, model_id: modelId, voice_settings: settings });
  fs.writeFileSync(file, Buffer.from(await res.arrayBuffer()));
  const u = usage();
  u.characters += text.length;
  u.requests += 1;
  fs.writeFileSync(USAGE, JSON.stringify(u, null, 2));
  return { file, cached: false };
};

export const totalUsage = usage;
