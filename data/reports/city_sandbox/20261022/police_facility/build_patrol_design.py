"""Reproducible authored source-direction sector route; original geometry untouched."""
import json, math
from pathlib import Path
ROOT = Path(__file__).resolve().parents[5]
path = ROOT / 'game/assets/authored/police_patrol.json'
data = json.loads(path.read_text())
controls = [[36.5,-436.4],[47,-436.5],[61.6,-436.5],[70,-436],[73.7,-432.5],[74.3,-424],[74.4,-380],[73.8,-371],[71.8,-368.5],[68,-374.7],[61.34287662,-380.64211773],[40,-400.5],[12,-426.4],[3,-434.7],[-.4,-438],[1,-439],[6,-439.2],[20,-439.2],[32,-439.1],[37.5,-438.2],[40.5,-434],[42,-431.4],[42,-430]]
points = []
for i in range(len(controls)-1):
    p0, p1, p2, p3 = controls[max(0,i-1)], controls[i], controls[i+1], controls[min(len(controls)-1,i+2)]
    n = max(2, math.ceil(math.dist(p1,p2)/.25))
    for j in range(n):
        t = j/n
        points.append([.5*((2*p1[k])+(-p0[k]+p2[k])*t+(2*p0[k]-5*p1[k]+4*p2[k]-p3[k])*t*t+(-p0[k]+3*p1[k]-3*p2[k]+p3[k])*t*t*t) for k in range(2)])
points.append(controls[-1])
data['forward_sector_loop_control_xz'] = controls
data['forward_sector_loop_xz'] = points
path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n')
print('forward dense samples',len(points),'root',ROOT)
