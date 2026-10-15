// Lists ElevenLabs voices and models (names, ids, labels only). Never prints the key.
import { loadKey, listVoices, listModels } from "./elevenlabs.ts";
const key = loadKey();
if (!key) { console.log("no key"); process.exit(1); }
const models = await listModels(key);
for (const m of models) if (m.can_do_text_to_speech) console.log(`MODEL ${m.model_id} | ${m.name}`);
const { voices } = await listVoices(key);
for (const v of voices) {
  const l = v.labels ?? {};
  console.log(`VOICE ${v.voice_id} | ${v.name} | ${v.category} | ${l.gender ?? ""} ${l.age ?? ""} ${l.accent ?? ""} | ${l.descriptive ?? l.description ?? ""} | ${l.use_case ?? ""}`);
}
