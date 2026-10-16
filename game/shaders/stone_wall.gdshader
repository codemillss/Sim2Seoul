shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Original generated albedo informed by observed coursed granite, not a photo scan.
// World metre projection keeps the source wall meshes and all collision untouched.
uniform sampler2D granite_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 stone_tint : source_color = vec4(0.91, 0.90, 0.86, 1.0);
uniform float repeat_size_m = 1.8;
uniform float top_height_m = 2.0;
uniform bool coping_only = false;
varying vec3 position_world;
varying vec3 normal_world;

void vertex() {
 position_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 normal_world = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise2(vec2 p) {
 vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);
}
void fragment() {
 vec3 face=normalize(normal_world);
 vec2 tangent=normalize(vec2(-face.z, face.x)+vec2(0.00001));
 float along=dot(position_world.xz,tangent);
 vec2 uv=vec2(along,-position_world.y)/repeat_size_m;
 vec3 sampled=texture(granite_albedo,uv).rgb;
 float tone=noise2(vec2(along,position_world.y)*0.63);
 float near_detail=1.0-smoothstep(14.0,50.0,distance(CAMERA_POSITION_WORLD,position_world));
 vec3 masonry=sampled*stone_tint.rgb*mix(0.94,1.04,tone);
 // Damp weathering is restrained at the base, not black polygon outlines.
 float damp=(1.0-smoothstep(0.05,0.50,position_world.y))*mix(0.05,0.16,tone);
 masonry*=1.0-damp;
 float ribs=cos(along*28.0);
 float seams=1.0-smoothstep(0.01,0.04,abs(sin((position_world.x+position_world.z)*12.0)));
 vec3 tile=vec3(0.13,0.15,0.16)*(0.93+ribs*0.12);
 tile*=1.0-seams*0.13;
 float coping=coping_only?1.0:smoothstep(top_height_m-0.23,top_height_m-0.18,position_world.y);
 ALBEDO=mix(masonry,tile,coping);
 ROUGHNESS=mix(0.92,0.73,coping);
 SPECULAR=mix(0.23,0.33,coping);
 // Derivative bump works on the existing meshes without tangent/UV attributes.
 float relief=(dot(sampled,vec3(0.299,0.587,0.114))-0.45)*0.0015*near_detail*(1.0-coping);
 vec3 dpdx=dFdx(VERTEX); vec3 dpdy=dFdy(VERTEX);
 vec3 r1=cross(dpdy,NORMAL); vec3 r2=cross(NORMAL,dpdx);
 float det=dot(dpdx,r1);
 vec3 gradient=sign(det)*(dFdx(relief)*r1+dFdy(relief)*r2);
 NORMAL=normalize(max(abs(det),0.00001)*NORMAL-gradient);
}
