import sys, math, struct, wave, subprocess, os, time
SINK='alsa_output.platform-sound.HiFi__Speaker__sink'
SRC='alsa_input.platform-sound.HiFi__Mic__source'
rate=48000
def tone(ch,f,path,secs=1.2,amp=0.063):
    n=int(rate*secs); fade=int(rate*0.02)
    w=wave.open(path,'wb'); w.setnchannels(4); w.setsampwidth(2); w.setframerate(rate)
    b=bytearray()
    for i in range(n):
        g=min(1.0,i/fade,(n-1-i)/fade); v=int(32767*amp*g*math.sin(2*math.pi*f*i/rate))
        s=[0,0,0,0]; s[ch-1]=v; b+=struct.pack('<4h',*s)
    w.writeframes(bytes(b)); w.close()
def level(path,f):
    w=wave.open(path); nch=w.getnchannels(); sr=w.getframerate(); raw=w.readframes(w.getnframes()); w.close()
    x=struct.unpack('<%dh'%(len(raw)//2), raw)
    x=[sum(x[i:i+nch])/nch for i in range(0,len(x),nch)]
    x=x[int(0.35*sr):int(1.1*sr)]           # steady middle of the tone
    k=2*math.pi*f/sr; c=2*math.cos(k); s1=s2=0.0
    for v in x: s0=v+c*s1-s2; s2=s1; s1=s0
    p=s1*s1+s2*s2-c*s1*s2
    return 10*math.log10(max(p,1e-9)/len(x)**2)
res={}
for f in (200,4000):
  for ch in (1,2,3,4):
    t=f'/tmp/spk_t.wav'; r=f'rec_{ch}_{f}.wav'
    tone(ch,f,t)
    rec=subprocess.Popen(['pw-record','--target',SRC,'--rate','48000','--channels','2','--format','s16',r])
    time.sleep(0.25)
    subprocess.run(['pw-play','--target',SINK,t],check=True)
    time.sleep(0.2); rec.terminate(); rec.wait()
    res[(ch,f)]=level(r,f)
    time.sleep(0.4)
names={1:'FL',2:'FR',3:'RL',4:'RR'}
print('ch       200 Hz   4 kHz   (dB, relative)   200-minus-4k')
for ch in (1,2,3,4):
    a,b=res[(ch,200)],res[(ch,4000)]
    print(f'{ch} {names[ch]}   {a:7.1f} {b:7.1f}            {a-b:7.1f}')
