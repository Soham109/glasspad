import subprocess, numpy as np, sys
from scipy import ndimage
p=sys.argv[1]; W,H=int(sys.argv[2]),int(sys.argv[3]); s=4
w,h=W//s,H//s
raw=subprocess.run(["ffmpeg","-v","error","-i",p,"-vf",f"scale={w}:{h},format=gray","-f","rawvideo","-"],capture_output=True).stdout
fr=np.frombuffer(raw,dtype=np.uint8).reshape(-1,h,w)
prev=None
for i,f in enumerate(fr):
    m=(f>30)&(f<90)
    m[:, :30]=False; m[:, -30:]=False; m[:int(h*0.16),:]=False  # ignore edges / island / pill
    lab,n=ndimage.label(m)
    sizes=ndimage.sum(m,lab,range(1,n+1)) if n else []
    blobs=[(ndimage.center_of_mass(m,lab,k+1)) for k,sz in enumerate(sizes) if 250<sz<1500]
    sig=(len(blobs), tuple((round(b[1]/w,2),round(b[0]/h,2)) for b in blobs))
    if prev is None or sig[0]!=prev[0] or i%30==0:
        print(f"{i:4d} {i/60:6.3f}s n={sig[0]} {sig[1]}")
    prev=sig
