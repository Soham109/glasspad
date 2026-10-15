"""Tiny ElevenLabs client for the film voice. Reads ELEVENLABS_API_KEY from the environment or
promo/.env at runtime; the key is never printed, logged or written. Every call is cached by a
hash of its inputs in voice/cache-film, so re-running never spends characters twice.

    tts(voice_id, model_id, text, settings, previous_text=None, next_text=None)
      -> (mp3_path, alignment_dict)
"""
import base64, hashlib, json, os, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CACHE = os.path.join(ROOT, "voice", "cache-film")
API = "https://api.elevenlabs.io"


def key():
    k = os.environ.get("ELEVENLABS_API_KEY")
    if k:
        return k.strip()
    env = os.path.join(ROOT, ".env")
    if os.path.exists(env):
        for line in open(env):
            if line.strip().startswith("ELEVENLABS_API_KEY"):
                return line.split("=", 1)[1].strip().strip("'\"")
    return None


def _post(path, body):
    k = key()
    if not k:
        raise SystemExit("no ElevenLabs key")
    req = urllib.request.Request(API + path, data=json.dumps(body).encode(), method="POST",
                                 headers={"xi-api-key": k, "content-type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        msg = e.read().decode(errors="replace")[:400].replace(k, "[redacted]")
        raise SystemExit(f"ElevenLabs {path.split('?')[0]} failed: {e.code} {msg}")


def tts(voice_id, model_id, text, settings, previous_text=None, next_text=None, seed=None):
    os.makedirs(CACHE, exist_ok=True)
    spec = dict(v=voice_id, m=model_id, t=text, s=settings, p=previous_text, n=next_text, seed=seed, f="mp3_44100_128")
    h = hashlib.sha256(json.dumps(spec, sort_keys=True).encode()).hexdigest()[:20]
    mp3, js = os.path.join(CACHE, h + ".mp3"), os.path.join(CACHE, h + ".json")
    if os.path.exists(mp3) and os.path.exists(js):
        return mp3, json.load(open(js))
    body = dict(text=text, model_id=model_id, voice_settings=settings)
    if previous_text:
        body["previous_text"] = previous_text
    if next_text:
        body["next_text"] = next_text
    if seed is not None:
        body["seed"] = seed
    d = _post(f"/v1/text-to-speech/{voice_id}/with-timestamps?output_format=mp3_44100_128", body)
    open(mp3, "wb").write(base64.b64decode(d["audio_base64"]))
    align = d.get("normalized_alignment") or d.get("alignment") or {}
    json.dump(dict(spec=spec, alignment=align), open(js, "w"))
    usage = os.path.join(CACHE, "usage.json")
    u = json.load(open(usage)) if os.path.exists(usage) else dict(characters=0, requests=0)
    u["characters"] += len(text)
    u["requests"] += 1
    json.dump(u, open(usage, "w"))
    return mp3, dict(spec=spec, alignment=align)
