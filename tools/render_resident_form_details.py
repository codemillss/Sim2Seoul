"""Render source .blend details with fixed cameras, without modifying source.

Run in Blender with -- --input <blend> --output-dir <fresh directory>.
Both comparison cohorts use identical cameras and the saved EXP35/36 neutral
studio lights. These are actual Blender renders, not game screenshots.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,required=True)
    parser.add_argument('--output-dir',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    source=args.input.resolve();before=sha(source)
    destination=args.output_dir.resolve()
    if destination.exists():
        raise RuntimeError('Fresh detail output directory required')
    destination.mkdir(parents=True)
    bpy.ops.wm.open_mainfile(filepath=str(source))
    scene=bpy.context.scene;camera=scene.camera
    scene.render.resolution_x=900;scene.render.resolution_y=900
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    camera.data.type='ORTHO'
    views=[('face_front',(0,-2,1.665),(0,0,1.665),.34),
           ('face_right',(-2,0,1.665),(0,0,1.665),.34),
           ('hand_left_front',(.48,-2,.83),(.48,-.03,.83),.29),
           ('foot_left_oblique',(.43,-.65,.34),(.105,-.07,.055),.34),
           ('pelvis_back',(0,2,1.0),(0,0,1.0),.64)]
    captures=[]
    for name,position,target,scale in views:
        camera.location=position
        camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
        camera.data.ortho_scale=scale
        path=destination/(name+'.png');scene.render.filepath=str(path)
        bpy.ops.render.render(write_still=True)
        captures.append({'file':str(path),'sha256':sha(path),'view':name,
                         'camera_location':position,'camera_target':target,'orthographic_scale':scale})
    after=sha(source)
    if before!=after:
        raise RuntimeError('Review mutated .blend bytes')
    record={'task':'EXP36_UNALTERED_SOURCE_DETAIL_RENDERS',
            'created_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'source':str(source),'source_sha256_before':before,'source_sha256_after':after,
            'render_script_sha256':sha(Path(__file__)),
            'image_type':'Actual Blender neutral-studio renders, no image editing. Not Godot gameplay.',
            'captures':captures,'art_acceptance':False}
    (destination/'renders.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
    print('EXP36_DETAIL_REVIEW_READY',len(captures))


if __name__=='__main__':
    main()
