#!/usr/bin/env python3
"""Deterministic original game sounds; no recordings or third-party samples."""
from pathlib import Path
import array, hashlib, json, math, random, wave

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'game/assets/audio/city_vehicles'
RATE = 22050


def make(kind, seconds):
    rng = random.Random('Sim2Seoul-original-' + kind)
    values = []; low = 0.; phase = 0.
    for i in range(round(RATE * seconds)):
        t = i / RATE
        noise = rng.uniform(-1., 1.); low += .12 * (noise - low)
        if kind in ('engine', 'diesel'):
            fundamental = 55. if kind == 'engine' else 45.
            pulse = .78 + .22 * math.sin(math.tau * 12 * t)
            value = pulse * (.46 * math.sin(math.tau * fundamental*t) + .23*math.sin(math.tau*fundamental*2*t) + .12*math.sin(math.tau*fundamental*3*t)) + .19*low
        elif kind == 'tyres':
            value = .7 * (noise-low) + .3*low
        elif kind in ('police_siren', 'fire_siren'):
            frequency = 790. + 270.*math.sin(math.tau*t) if kind == 'police_siren' else (540. if int(t*2)%2==0 else 720.)
            phase += math.tau*frequency/RATE
            value = .76*math.sin(phase) + .18*math.sin(phase*2) + .06*math.sin(phase*3)
        elif kind == 'rotor':
            pulse = (.5 + .5*math.sin(math.tau*18*t))**3
            value = (.22+.78*pulse)*(.55*low + .27*math.sin(math.tau*72*t) + .18*math.sin(math.tau*144*t))
        elif kind == 'rain':
            value = .8*low + .18*noise + (.08*math.sin(math.tau*1100*t) if rng.random()<.012 else 0.)
        elif kind == 'water':
            value = (.8 + .2*math.sin(math.tau*7*t))*(.65*low + .35*noise)
        else:
            envelope = math.sin(math.pi*min(1.,t/seconds))**.8
            value = envelope*(.8*low + .2*noise)
        values.append(value)
    # A circular crossfade keeps deterministic noise/tone loops free of clicks.
    fade = min(round(.035*RATE), len(values)//8)
    if kind != 'door_air':
        for i in range(fade):
            f = i/max(1,fade-1); shared = values[-fade+i]*(1-f) + values[i]*f
            values[-fade+i] = shared
        values=values[fade:]
    maximum = max(abs(x) for x in values) or 1.
    return array.array('h', (round(max(-1.,min(1.,x/maximum*.55))*32767) for x in values))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rows=[]
    for kind,seconds in [('engine',2),('diesel',2),('tyres',2),('police_siren',4),('fire_siren',4),('rotor',2),('rain',4),('water',2),('door_air',.7)]:
        path=OUT/(kind+'.wav');samples=make(kind,seconds)
        with wave.open(str(path),'wb') as f:
            f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE);f.writeframes(samples.tobytes())
        rows.append({'path':path.relative_to(ROOT).as_posix(),'seconds':len(samples)/RATE,'sample_rate_hz':RATE,'channels':1,'peak_linear':max(abs(v) for v in samples)/32768.,'loop_seam_jump_linear':abs(samples[-1]-samples[0])/32768.,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    (OUT/'provenance.json').write_text(json.dumps({'author':'Sim2Seoul project','method':'Original deterministic procedural synthesis using Python standard library. No third-party samples or recordings.','license':'No separate project distribution license is designated. Original project-generated audio with no third-party samples; see docs/ATTRIBUTION.md.','real_vehicle_recording':False,'scope':'Game sound design, not exact Korean emergency-service recordings.','generator':'tools/make_city_vehicle_audio.py','files':rows},ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'sounds':len(rows),'folder':str(OUT.relative_to(ROOT))}))


if __name__=='__main__':main()
