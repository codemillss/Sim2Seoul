"""Build the original editable EXP35 clay study using Blender 4.5 LTS.

Usage: Blender --background --factory-startup --python this.py --
       --output-dir game/assets/original/resident_study --render-dir ...

No old character is an input. The .blend retains the authored control cage,
unapplied subdivision, named anatomy loops, new armature and pose supports.
The GLB has subdivision baked identically into Basis and corrective shapes.
"""
from __future__ import annotations
import argparse,datetime,hashlib,json,math,sys
from pathlib import Path
import bpy,bmesh
from mathutils import Vector

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from build_body_cage import build_body
from build_head_extremities import extend_anatomy
from build_study_rig import assign_rig,apply_study_pose,POSE_KEYS,CORRECTIVES


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def write_json(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')


def clay_material():
    material=bpy.data.materials.new('Study_Neutral_Clay');material.use_nodes=True
    material.diffuse_color=(.38,.40,.42,1.)
    shader=material.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value=(.38,.40,.42,1.)
    shader.inputs['Roughness'].default_value=.65
    shader.inputs['Metallic'].default_value=0.
    return material


def recalculate(obj):
    bm=bmesh.new();bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(obj.data);bm.free();obj.data.update()


def remove_unused_vertices(obj,info):
    """Remove cut-out orbital grid points, remapping all authored ID contracts."""
    used=sorted({int(i) for p in obj.data.polygons for i in p.vertices})
    remap={old:new for new,old in enumerate(used)}
    vertices=[tuple(obj.data.vertices[i].co) for i in used]
    faces=[tuple(remap[i] for i in p.vertices) for p in obj.data.polygons]
    mesh=bpy.data.meshes.new('ResidentStudy_CleanControlCage');mesh.from_pydata(vertices,[],faces);mesh.update()
    for polygon in mesh.polygons:polygon.use_smooth=True
    old=obj.data;old_count=len(old.vertices);obj.data=mesh
    if old.users==0:bpy.data.meshes.remove(old)
    for key,ids in info['vertex_regions'].items():info['vertex_regions'][key]=[remap[i] for i in ids if i in remap]
    for key,ids in info.get('anatomy_loops',{}).items():info['anatomy_loops'][key]=[remap[i] for i in ids if i in remap]
    for value in info['boundaries'].values():value['indices']=[remap[i] for i in value['indices']]
    info['removed_unused_vertices']=old_count-len(remap)


def topology_snapshot(obj):
    bm=bmesh.new();bm.from_mesh(obj.data)
    result={'control_vertices':len(bm.verts),'control_edges':len(bm.edges),'control_faces':len(bm.faces),
            'quad_faces':sum(len(f.verts)==4 for f in bm.faces),
            'triangle_faces':sum(len(f.verts)==3 for f in bm.faces),
            'boundary_edges':sum(e.is_boundary for e in bm.edges),
            'nonmanifold_nonboundary_edges':sum(not e.is_manifold and not e.is_boundary for e in bm.edges),
            'loose_vertices':sum(not v.link_faces for v in bm.verts),
            'authorship':'Explicit editable cage with stitched boundaries and orbital/finger loops; no isosurface/scan/old mesh read.'}
    bm.free();return result


def bake_subdivision(cage,rig):
    """Evaluate the exact same topology for Basis and all pose supports."""
    apply_study_pose(rig,'a_pose',[cage])
    skin=[m for m in cage.modifiers if m.type=='ARMATURE']
    old_skin=[m.show_viewport for m in skin]
    for m in skin:m.show_viewport=False
    deps=bpy.context.evaluated_depsgraph_get()
    def evaluate():
        cage.data.update();bpy.context.view_layer.update();deps.update()
        evaluated=cage.evaluated_get(deps)
        mesh=bpy.data.meshes.new_from_object(evaluated,preserve_all_data_layers=True,depsgraph=deps)
        return mesh
    for key in cage.data.shape_keys.key_blocks:key.value=0.
    basis=evaluate();coords={}
    for name in CORRECTIVES:
        cage.data.shape_keys.key_blocks[name].value=1.;mesh=evaluate()
        assert len(mesh.vertices)==len(basis.vertices),'Subdivision changed morph topology'
        coords[name]=[v.co.copy() for v in mesh.vertices]
        bpy.data.meshes.remove(mesh);cage.data.shape_keys.key_blocks[name].value=0.
    render=bpy.data.objects.new('ResidentStudy_RenderSurface',basis)
    bpy.context.scene.collection.objects.link(render)
    render.matrix_world=cage.matrix_world.copy()
    for group in cage.vertex_groups:render.vertex_groups.new(name=group.name)
    # new_from_object retains evaluated deform weights and their group indices.
    assert all(v.groups for v in render.data.vertices),'Evaluated mesh lost skin weights'
    render.shape_key_add(name='Basis')
    for name in CORRECTIVES:
        key=render.shape_key_add(name=name)
        for dst,src in zip(key.data,coords[name]):dst.co=src
    render.parent=rig
    modifier=render.modifiers.new('StudySkinning','ARMATURE');modifier.object=rig
    source_keys=cage.data.shape_keys;target_keys=render.data.shape_keys
    target_keys.animation_data_create()
    for source in source_keys.animation_data.nla_tracks:
        track=target_keys.animation_data.nla_tracks.new();track.name=source.name;track.mute=source.mute
        for original in source.strips:
            strip=track.strips.new(original.name,int(original.frame_start),original.action)
            strip.action_frame_start=original.action_frame_start;strip.action_frame_end=original.action_frame_end
            if hasattr(strip,'action_slot') and hasattr(original,'action_slot'):strip.action_slot=original.action_slot
    for m,value in zip(skin,old_skin):m.show_viewport=value
    bpy.context.view_layer.update()
    return render


def aim(obj,target):obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()


def render_reviews(cage,rig,destination):
    destination.mkdir(parents=True,exist_ok=True);scene=bpy.context.scene
    scene.render.engine='BLENDER_EEVEE_NEXT';scene.render.resolution_x=900;scene.render.resolution_y=1100
    scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
    scene.render.film_transparent=False;scene.world.color=(.16,.16,.16)
    scene.view_settings.view_transform='AgX'
    scene.render.image_settings.color_mode='RGB'
    camera_data=bpy.data.cameras.new('StudyReviewCamera');camera=bpy.data.objects.new('StudyReviewCamera',camera_data)
    scene.collection.objects.link(camera);scene.camera=camera;camera_data.type='ORTHO';camera_data.ortho_scale=2.03
    for name,location,power,size in [('Key',(-2.2,-3.0,3.3),420,3.0),('Fill',(2.3,-1.8,2.),160,3.5),('Rim',(0,2.3,3.),300,2.5)]:
        light=bpy.data.lights.new('Study'+name,'AREA');light.energy=power;light.shape='DISK';light.size=size
        ob=bpy.data.objects.new('Study'+name,light);scene.collection.objects.link(ob);ob.location=location;aim(ob,(0,0,1.))
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.002));floor=bpy.context.object;floor.name='StudyReviewFloor'
    material=clay_material();floor.data.materials.append(material)
    positions={'front':(0,-4,1.15),'right':(-4,0,1.15),'back':(0,4,1.15),'front45':(-2.83,-2.83,1.15)}
    captures=[]
    for pose in POSE_KEYS:
        apply_study_pose(rig,pose,[cage])
        for view,position in positions.items():
            camera.location=position;aim(camera,(0,0,1.15));camera_data.ortho_scale=2.65
            path=destination/(pose+'_'+view+'.png');scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
            captures.append({'pose':pose,'view':view,'file':str(path),'sha256':sha(path),'renderer':'Blender EEVEE actual geometry render; orthographic fixed studio; not Godot gameplay.'})
    apply_study_pose(rig,'a_pose',[cage]);return captures


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output-dir',type=Path,required=True)
    parser.add_argument('--render-dir',type=Path);args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    destination=args.output_dir.resolve();destination.mkdir(parents=True,exist_ok=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    cage,info=build_body();cage,info=extend_anatomy(cage,info);remove_unused_vertices(cage,info);recalculate(cage)
    cage.name='ResidentStudy_EditableCage';cage.data.materials.clear();cage.data.materials.append(clay_material())
    cage['authored_source']='tools/sculpted_character/;original explicit control cage, no old asset input'
    cage['study_scope']='Neutral adult form study; no detailed genital geometry; no skin/garment/hair paint.'
    for name,ids in info.get('anatomy_loops',{}).items():
        group=cage.vertex_groups.new(name='anatomy_'+name);group.add(ids,1.,'REPLACE')
    # Rig skin groups must occupy its own indices; the anatomy groups are
    # retained for editing but ignored by skin export unless a bone matches.
    rig,rig_info=assign_rig(cage,info)
    apply_study_pose(rig,'a_pose',[cage])
    blend=destination/'resident_form_m01.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    render=bake_subdivision(cage,rig)
    bpy.ops.object.select_all(action='DESELECT');render.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig
    for data in [rig,render.data.shape_keys]:
        for track in data.animation_data.nla_tracks:track.mute=False
    glb=destination/'resident_form_m01.glb'
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,
        export_apply=False,export_yup=True,export_skins=True,export_animations=True,
        export_animation_mode='NLA_TRACKS',export_morph=True,export_force_sampling=True,
        export_optimize_animation_size=False,export_extras=True)
    for data in [rig,render.data.shape_keys]:
        for track in data.animation_data.nla_tracks:track.mute=True
    render.hide_render=True;render.hide_set(True);cage.hide_set(False);cage.hide_render=False
    captures=render_reviews(cage,rig,args.render_dir.resolve()) if args.render_dir else []
    bpy.ops.object.select_all(action='DESELECT');cage.select_set(True);bpy.context.view_layer.objects.active=cage
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                area.spaces.active.region_3d.view_location=(0,0,.95)
                area.spaces.active.region_3d.view_distance=3.0
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    result={'task':'EXP35_RESIDENT_FORM_STUDY','created_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'blender':bpy.app.version_string,'coordinate_contract':'Blender Zup/front-Y/left+X/soleZ0/target1.78m;GLB glTF Yup conversion.',
            'authors':'Sim2Seoul contributors; authored explicit control vertices/loops and original rig. Scripted cage modelling, not manual brush sculpting.',
            'source_assets_read':[],'old_resident_geometry_read':False,'image_paint_used':False,
            'topology':topology_snapshot(cage),'body_info':info,'rig':rig_info,
            'export_surface_vertices':len(render.data.vertices),'export_surface_faces':len(render.data.polygons),
            'files':{str(p.name):{'bytes':p.stat().st_size,'sha256':sha(p)} for p in [blend,glb]},
            'source_sha256':{str(p.resolve().relative_to(Path.cwd().resolve())):sha(p) for p in HERE.glob('*.py')},
            'captures':captures,'full_art_target_met':False,
            'scope':'One neutral adult male form study. Body/face/pose art requires actual review. No replacement of normal game characters, no mocap or photoreal result claim.'}
    write_json(destination/'FORM_STUDY_MANIFEST.json',result)
    print('EXP35_FORM_STUDY_READY',json.dumps({'control_vertices':result['topology']['control_vertices'],'export_vertices':result['export_surface_vertices'],'bones':rig_info['bone_count'],'glb':str(glb)}))


if __name__=='__main__':main()
