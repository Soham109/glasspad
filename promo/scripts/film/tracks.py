import subprocess, numpy as np, sys, json
from scipy import ndimage
p,out=sys.argv[1],sys.argv[2]; W,H=2622,1206; s=4; w,h=W//s,H//s
raw=subprocess.run(["ffmpeg","-v","error","-i",p,"-vf",f"scale={w}:{h},format=gray","-f","rawvideo","-"],capture_output=True).stdout
fr=np.frombuffer(raw,dtype=np.uint8).reshape(-1,h,w)
res=[]
for f in fr:
    m=(f>30)&(f<90); m[:, :30]=False; m[:, -30:]=False; m[:int(h*0.16),:]=False; m[int(h*0.92):,:]=False
    lab,n=ndimage.label(m); pts=[]
    for k in range(1,n+1):
        sz=(lab==k).sum()
        if 250<sz<1500:
            cy,cx=ndimage.center_of_mass(m,lab,k); pts.append([round(cx/w,4),round(cy/h,4)])
    res.append(sorted(pts,key=lambda q:q[1]))
json.dump(dict(fps=60,frames=res),open(out,"w"))
print(len(res))
