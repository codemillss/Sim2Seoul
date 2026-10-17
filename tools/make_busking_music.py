"""Deterministic original plucked-string study. No samples or existing song input."""
from pathlib import Path
import math, random, struct, wave, hashlib
RATE=32000
DURATION=20.0
SEED=17026
OUTPUT=Path(__file__).resolve().parents[1]/'game/assets/audio/stonewall_guitar.wav'
def render():
    rng=random.Random(SEED); samples=[0.0]*int(RATE*DURATION)
    # Authored Cmaj7 / Am7 / Fmaj7 / Gadd9 arpeggio, 96bpm, eight bars.
    chords=[[48,55,59,64,67,64,59,55],[45,52,55,60,64,60,55,52],
            [41,48,52,57,60,57,52,48],[43,50,57,62,67,62,57,50]]
    step=.625
    for bar in range(8):
        for beat,note in enumerate(chords[bar%4]):
            start=int((bar*4+beat*.5)*step*RATE)
            frequency=440*2**((note-69)/12)
            n=round(RATE/frequency); ring=[rng.uniform(-1,1) for _ in range(n)]
            for i in range(min(int(RATE*2.7),len(samples)-start)):
                at=i%n; sample=ring[at]; ring[at]=.497*(sample+ring[(at+1)%n])
                envelope=min(1,i/(RATE*.003))*math.exp(-i/(RATE*1.1))
                samples[start+i]+=.22*sample*envelope
    # Low-level repeat-safe tail; peak limit, fixed deterministic PCM.
    peak=max(abs(x) for x in samples); gain=.8/max(peak,.8)
    with wave.open(str(OUTPUT),'wb') as out:
        out.setparams((1,2,RATE,0,'NONE','not compressed'))
        out.writeframes(b''.join(struct.pack('<h',int(max(-1,min(1,x*gain*min(1,(len(samples)-i)/(RATE*.06))))*32767)) for i,x in enumerate(samples)))
    print(OUTPUT.name, OUTPUT.stat().st_size, hashlib.sha256(OUTPUT.read_bytes()).hexdigest())
if __name__=='__main__':render()
