"""Audition voices on the real script. Usage: python3 -I scripts/film/audition.py [model]
Writes voice/work/audition/<name>.mp3 and prints the measurements for each."""
import os, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import eleven, measure

TEXT = ("Your Mac is over there. Your phone is right here. Glasspad turns it into a trackpad. "
        "Swipe three fingers, and your Spaces move with your hand.")
VOICES = {
    "Chris": "iP95p4xoKVk53GoZ742B", "Will": "bIHbv24MWmeRgasZH58o", "Roger": "CwhRBWXzGAHq8TQ4Fs17",
    "Sarah": "EXAVITQu4vr4xnSDxMaL", "Matilda": "XrExE9yKIg1WjnnlVkGX", "Brian": "nPczCjzI2devNBz1zQrb",
    "River": "SAz9YHcvj6GT2YYXdXww",
}
SETTINGS = dict(stability=0.5, similarity_boost=0.75, style=0.0, use_speaker_boost=True)

model = sys.argv[1] if len(sys.argv) > 1 else "eleven_v4"
only = sys.argv[2].split(",") if len(sys.argv) > 2 else list(VOICES)
out = os.path.join(eleven.ROOT, "voice", "work", "audition")
os.makedirs(out, exist_ok=True)
for name in only:
    mp3, meta = eleven.tts(VOICES[name], model, TEXT, SETTINGS)
    dst = os.path.join(out, f"{name}-{model}.mp3")
    shutil.copy(mp3, dst)
    print(f"{name:8s}", measure.report(dst, meta["alignment"]))
