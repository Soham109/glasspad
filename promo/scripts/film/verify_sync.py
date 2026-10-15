"""Sync check on finished files. The picture is frame exact by construction (Remotion renders
the same timeline the mix uses), so what can drift is the audio after muxing and AAC encoding.
This measures that drift by cross-correlating the file's audio with the source mix, at the
start, middle and end, and reports durations.
  python3 -I scripts/film/verify_sync.py out/glasspad-film.mp4 public/v2/mix-film.wav"""
import subprocess, sys
import numpy as np
sr = 48000
def pcm(p):
    return np.frombuffer(subprocess.run(["ffmpeg", "-v", "error", "-i", p, "-ac", "1", "-ar", str(sr), "-f", "f32le", "-"], capture_output=True).stdout, np.float32)
def dur(p, sel):
    return float(subprocess.run(["ffprobe", "-v", "error", "-select_streams", sel, "-show_entries", "stream=duration", "-of", "csv=p=0", p], capture_output=True, text=True).stdout.strip() or 0)
f, ref = sys.argv[1], sys.argv[2]
a, b = pcm(f), pcm(ref)
for t in (8.0, len(b) / sr / 2, len(b) / sr - 6):
    i = int(t * sr); w = sr // 2; m = sr // 20
    seg = b[i:i + w]
    win = a[i - m:i + w + m]
    c = np.correlate(win, seg, "valid")
    lag = np.argmax(c) - m
    print(f"at {t:6.2f}s audio offset {lag / sr * 1000:+6.2f} ms (+ means late)")
print(f"video {dur(f, 'v:0'):.3f}s  audio {dur(f, 'a:0'):.3f}s  source mix {len(b) / sr:.3f}s")
