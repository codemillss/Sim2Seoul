extends Node3D
## Latest scene display only. Three authored time-of-day presets and source materials.
const STREET: Shader = preload("res://shaders/street_surface.gdshader")
var loaded := false
var load_error := ""
var ground_count := 0
var material_count := 0
var host: Node3D
var environment: Environment
var sky_material: ProceduralSkyMaterial
var sun: DirectionalLight3D
var time_profile := "day"

func setup(root_scene: Node3D) -> bool:
 host=root_scene
 var world_environment:=host.get_node("Presentation/WorldEnvironment") as WorldEnvironment
 environment=world_environment.environment.duplicate(true)
 world_environment.environment=environment
 sky_material=ProceduralSkyMaterial.new()
 sky_material.sky_top_color=Color(0.22,0.39,0.59)
 sky_material.sky_horizon_color=Color(0.72,0.77,0.78)
 sky_material.ground_bottom_color=Color(0.27,0.28,0.24)
 sky_material.ground_horizon_color=Color(0.68,0.72,0.73)
 sky_material.sky_curve=0.24
 var sky:=Sky.new();sky.sky_material=sky_material
 environment.sky=sky
 environment.background_mode=Environment.BG_SKY
 environment.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
 environment.ambient_light_energy=0.48
 environment.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
 environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
 environment.tonemap_exposure=1.0
 environment.ssao_radius=1.1
 environment.ssao_intensity=1.25
 environment.ssao_power=1.25
 environment.fog_enabled=true
 environment.fog_light_color=Color(0.72,0.77,0.79)
 environment.fog_density=0.00032
 sun=host.get_node("Presentation/Sun") as DirectionalLight3D
 sun.rotation_degrees=Vector3(-47,-38,0)
 sun.light_color=Color(1.0,0.95,0.86)
 sun.light_energy=1.25
 sun.directional_shadow_max_distance=230.0
 var materials:=[]
 for index in range(4):
  var material:=ShaderMaterial.new();material.shader=STREET
  material.set_shader_parameter("kind",index);materials.append(material)
 var data=JSON.parse_string(FileAccess.get_file_as_string("res://resources/world_geometry/world.json"))
 for entry in data.meshes:
  if entry.role not in ["Routes","Ground"]:continue
  var visual: MeshInstance3D=host.city.source_nodes.get(entry.id)
  if visual==null or not visual.visible:continue
  var kind:=0
  if entry.material=="drive":kind=1
  elif entry.material=="grass":kind=2
  elif entry.material=="land":kind=3
  visual.material_override=materials[kind];ground_count+=1
 var support: StaticBody3D=host.city.fragments.get("W03_support")
 if support!=null:
  (support.get_parent() as MeshInstance3D).material_override=materials[0]
 for item in host.city_visuals.bundle.landmarks:
  if item.id!="plaza":continue
  for entry in item.components:
   var visual: MeshInstance3D=host.city_visuals.components.get(entry.id)
   if visual!=null:visual.material_override=materials[2 if entry.material=="grass" else 0]
 material_count=materials.size()
 loaded=true
 apply_quality(host.quality_id)
 print("PHOTO_ATMOSPHERE_READY ground=",ground_count)
 return true

func set_time_profile(id: String) -> bool:
 if id not in ["day","evening","night"] or environment==null:return false
 time_profile=id
 match id:
  "day":
   sky_material.sky_top_color=Color(.22,.39,.59)
   sky_material.sky_horizon_color=Color(.72,.77,.78)
   sky_material.ground_bottom_color=Color(.27,.28,.24)
   sky_material.ground_horizon_color=Color(.68,.72,.73)
   sun.rotation_degrees=Vector3(-47,-38,0)
   sun.light_color=Color(1.,.95,.86);sun.light_energy=1.25
   environment.ambient_light_energy=.48;environment.tonemap_exposure=1.
   environment.fog_light_color=Color(.72,.77,.79);environment.fog_density=.00032
  "evening":
   sky_material.sky_top_color=Color(.10,.15,.30)
   sky_material.sky_horizon_color=Color(.78,.47,.30)
   sky_material.ground_bottom_color=Color(.15,.15,.19)
   sky_material.ground_horizon_color=Color(.46,.32,.29)
   sun.rotation_degrees=Vector3(-9,-110,0)
   sun.light_color=Color(1.,.67,.39);sun.light_energy=.46
   environment.ambient_light_energy=.65;environment.tonemap_exposure=1.15
   environment.fog_light_color=Color(.35,.27,.31);environment.fog_density=.00025
  "night":
   sky_material.sky_top_color=Color(.012,.020,.055)
   sky_material.sky_horizon_color=Color(.055,.075,.14)
   sky_material.ground_bottom_color=Color(.025,.032,.055)
   sky_material.ground_horizon_color=Color(.055,.065,.10)
   sun.rotation_degrees=Vector3(-35,30,0)
   sun.light_color=Color(.50,.64,.95);sun.light_energy=.23
   environment.ambient_light_energy=.80;environment.tonemap_exposure=1.25
   environment.fog_light_color=Color(.045,.06,.10);environment.fog_density=.00018
 return true

func apply_quality(id: String) -> void:
 if environment!=null:environment.ssao_enabled=id=="standard"
 if is_instance_valid(host):host.get_viewport().msaa_3d=Viewport.MSAA_4X if id=="standard" else Viewport.MSAA_DISABLED
