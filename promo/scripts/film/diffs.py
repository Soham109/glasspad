import subprocess, numpy as np, sys
p=sys.argv[1]; w,h=150,326
raw=subprocess.run(["ffmpeg","-v","error","-i",p,"-vf",f"scale={w}:{h},format=gray","-f","rawvideo","-"],capture_output=True).stdout
fr=np.frombuffer(raw,dtype=np.uint8).reshape(-1,h,w).astype(float)
d=np.abs(np.diff(fr,axis=0)).mean((1,2))
for i,v in enumerate(d):
    if v>0.02: print(f"{i+1:4d} {(i+1)/60:6.3f}s diff {v:5.2f}")
