shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform int kind = 0; // 0 pedestrian paving, 1 asphalt, 2 lawn, 3 earth
varying vec3 world_position;
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
float hash21(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise2(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);}
void fragment(){
 vec2 p=world_position.xz;
 float near_detail=1.0-smoothstep(25.0,90.0,distance(CAMERA_POSITION_WORLD,world_position));
 float grain=noise2(p*65.0);
 vec3 c=vec3(0.52,0.51,0.47);
 if(kind==0){
  float row=floor(p.y/0.48);vec2 cell=vec2((p.x+mod(row,2.0)*0.34)/0.68,p.y/0.48);
  vec2 edge=min(fract(cell),1.0-fract(cell))*vec2(0.68,0.48);
  float joint=1.0-smoothstep(0.004,0.012+fwidth(p.x),min(edge.x,edge.y));
  float block=hash21(floor(cell));c*=mix(0.91,1.09,block);c=mix(c,c*0.63,joint*near_detail*0.60);
 }else if(kind==1){c=vec3(0.15,0.16,0.17)*mix(0.93,1.07,noise2(p*0.3));}
 else if(kind==2){c=mix(vec3(0.20,0.29,0.11),vec3(0.36,0.43,0.19),noise2(p*0.8));c*=0.94+noise2(p*15.0)*0.12;}
 else{c=vec3(0.54,0.49,0.38)*mix(0.94,1.05,noise2(p*1.6));}
 ALBEDO=c*(1.0+(grain-0.5)*0.10*near_detail);
 ROUGHNESS=0.94;SPECULAR=0.22;
}
