import subprocess,time,sys
src=open(__import__('os').path.join(__import__('os').path.dirname(__file__),'speaker-id-measure.py')).read().split('res={}')[0]; exec(src)
F=(150,300,600,1000,2000,4000,8000)
res={}
for f in F:
  for ch in (1,2,3,4):
    t='/tmp/spk_t.wav'; r=f'sw_{ch}_{f}.wav'
    tone(ch,f,t,amp=0.1)
    rec=subprocess.Popen(['pw-record','--target',SRC,'--rate','48000','--channels','2','--format','s16',r]); time.sleep(0.25)
    subprocess.run(['pw-play','--target',SINK,t],check=True); time.sleep(0.2); rec.terminate(); rec.wait()
    res[(ch,f)]=level(r,f); time.sleep(0.3)
print('Hz     ch1 FL  ch3 RL  (1-3)   |  ch2 FR  ch4 RR  (2-4)')
for f in F:
    a,b,c,d=res[(1,f)],res[(3,f)],res[(2,f)],res[(4,f)]
    print(f'{f:5d}  {a:6.1f} {b:6.1f} {a-b:+6.1f}   |  {c:6.1f} {d:6.1f} {c-d:+6.1f}')
