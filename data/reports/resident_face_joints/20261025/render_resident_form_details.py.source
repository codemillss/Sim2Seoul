"""Render source .blend details with fixed cameras, without modifying source.

Run in Blender with -- --input <blend> --output-dir <fresh directory>.
Both comparison cohorts use identical cameras and the saved EXP35/36/37 neutral
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
    parser.add_argument('--pose-source-dir',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    source=args.input.resolve();before=sha(source)
    destination=args.output_dir.resolve()
    if destination.exists():
        raise RuntimeError('Fresh detail output directory required')
    destination.mkdir(parents=True)
    bpy.ops.wm.open_mainfile(filepath=str(source))
    sys.path.insert(0,str(args.pose_source_dir.resolve()))
    from build_study_rig import apply_study_pose
    cage=bpy.data.objects['ResidentStudy_EditableCage'];rig=cage.parent
    scene=bpy.context.scene;camera=scene.camera
    scene.render.resolution_x=900;scene.render.resolution_y=900
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    camera.data.type='ORTHO'
    views=[('face_front','a_pose',(0,-2,1.665),(0,0,1.665),.34),
           ('face_right','a_pose',(-2,0,1.665),(0,0,1.665),.34),
           ('face_front45','a_pose',(-1.414,-1.414,1.665),(0,0,1.665),.34),
           ('ear_left','a_pose',(.6,-.14,1.65),(.075,0,1.65),.13),
           ('hand_left_front','a_pose',(.48,-2,.83),(.48,-.03,.83),.29),
           ('foot_left_oblique','a_pose',(.43,-.65,.34),(.105,-.07,.055),.34),
           ('shoulder_raise_front','arm_raise',(0,-2,1.44),(0,0,1.44),.72),
           ('shoulder_raise_back','arm_raise',(0,2,1.44),(0,0,1.44),.72),
           ('pelvis_squat_back','deep_squat',(0,2,.63),(0,0,.63),.78),
           ('pelvis_squat_right','deep_squat',(-2,0,.63),(0,0,.63),.78)]
    captures=[]
    for name,pose,position,target,scale in views:
        apply_study_pose(rig,pose,[cage])
        camera.location=position
        camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
        camera.data.ortho_scale=scale
        path=destination/(name+'.png');scene.render.filepath=str(path)
        bpy.ops.render.render(write_still=True)
        captures.append({'file':str(path),'sha256':sha(path),'view':name,'pose':pose,
                         'camera_location':position,'camera_target':target,'orthographic_scale':scale})
    after=sha(source)
    if before!=after:
        raise RuntimeError('Review mutated .blend bytes')
    record={'task':'EXP37_UNALTERED_SOURCE_DETAIL_RENDERS',
            'created_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'source':str(source),'source_sha256_before':before,'source_sha256_after':after,
            'render_script_sha256':sha(Path(__file__)),
            'pose_source':str(args.pose_source_dir.resolve()/'build_study_rig.py'),
            'pose_source_sha256':sha(args.pose_source_dir.resolve()/'build_study_rig.py'),
            'image_type':'Actual Blender neutral-studio renders, no image editing. Not Godot gameplay.',
            'captures':captures,'art_acceptance':False}
    (destination/'renders.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
    print('EXP37_DETAIL_REVIEW_READY',len(captures))


if __name__=='__main__':
    main()
