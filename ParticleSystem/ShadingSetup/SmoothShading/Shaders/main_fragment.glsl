#version 330
uniform mat4 projection_transform;

in VertexData
{
	vec2 param;
	vec3 fcolor;
	float z_orig;
	float z_maxdelta;
	vec4 world_cam_x_dir;
	vec4 world_cam_y_dir;
	vec4 world_cam_z_dir;
};

out Fragdata
{
	vec4 uv_colorindex_none;
	vec4 normal_depth;
};

void main ()
{
	vec2 cparam = 2 * (param - 0.5f);
	float dist2 = dot(cparam, cparam);

	if(dist2 > 1)
		discard;

	float z_delta = sqrt(1 - dist2) * z_maxdelta;
	vec4 z = projection_transform * vec4(0, 0, z_orig, 1);
	z /= z.w;

	vec4 zd = projection_transform * vec4(0, 0, z_orig + z_delta, 1);
	zd /= zd.w;

	gl_FragDepth = normal_depth.w = (gl_FragCoord.z + zd.z) - z.z;
	normal_depth.xyz = world_cam_x_dir.xyz * cparam.x + world_cam_y_dir.xyz * cparam.y + world_cam_z_dir.xyz * sqrt(1 - dist2);

	uv_colorindex_none = vec4(param, 0.5f, 0);
}