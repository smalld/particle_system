/*
 *  Expected declarations in the prepended code
 */
//#version 440
//layout(local_size_x= ... , local_size_y= ...) in;
//#define T_LAYOUT_IN {2}
//#define T_LAYOUT_OUT {3}
//#define T_IMAGE image2D
//#define T_PIXEL vec4
//#line 1

////////////////////////////////////////////////////////////////////////////////
//constants//
const int c_WorkGroupSize = int(gl_WorkGroupSize.x * gl_WorkGroupSize.y);
const int c_OccludersRimSize = 1;
const int c_OccludersGroupSizeX = int(gl_WorkGroupSize.x + c_OccludersRimSize * 2);
const int c_OccludersGroupSizeY = int(gl_WorkGroupSize.y + c_OccludersRimSize * 2);
const int c_OccludersGroupSize = c_OccludersGroupSizeX * c_OccludersGroupSizeY;
const int c_MaxLocalOccluders = 4;
const int c_MaxOccludersCount = c_MaxLocalOccluders * c_OccludersGroupSize;
const int c_MaxSamplesCount = min(128, c_MaxOccludersCount);
const float c_PI = 3.141592654f;
const float c_TWO_PI = 2 * 3.141592654f;
/*const int[] c_NeighbourOffsets = 
{
	0,
	-int(gl_WorkGroupSize.x + 1), int(gl_WorkGroupSize.x + 1), 
	-int(gl_WorkGroupSize.x), int(gl_WorkGroupSize.x), 
	-int(gl_WorkGroupSize.x - 1), int(gl_WorkGroupSize.x - 1), 
	-1, +1, 
};*/
const int[] c_NeighbourOffsets = 
{
	0,
	-int(c_OccludersGroupSizeX + 1), int(c_OccludersGroupSizeX + 1),
	-int(c_OccludersGroupSizeX - 1), int(c_OccludersGroupSizeX - 1), 
	-1, +1,
	-int(c_OccludersGroupSizeX), int(c_OccludersGroupSizeX), 
};

////////////////////////////////////////////////////////////////////////////////
//types//
struct Occluder
{
	vec3 Position;
	float Radius;
};

struct Sample
{
	vec4 Position;
	vec4 CamPosition;
	vec3 N;
	float CamDist;
};

////////////////////////////////////////////////////////////////////////////////
//uniforms//

/*
 * randomized vec2. Shall be uniformly distributed. Look for some advice, how to 
 * make it properly. They will be randomly rotated per pixel
 */
uniform vec2[256] u_SamplingPattern;

/*
 * images
 */
// texture holding depth in projection space and normal in camera space
layout(T_LAYOUT_IN) restrict /*coherent, volatile, readonly, writeonly*/ uniform image2D u_NormalDepth;
// computed ambient occlusion estimate
layout(T_LAYOUT_OUT) restrict /*coherent, volatile, restrict, readonly, writeonly*/ uniform image2D u_Target;

/*
 * model-view matrices 
 */
uniform mat4 modelviewprojection_transform;
uniform mat4 modelviewprojection_inv_transform;
uniform mat4 projection_transform;
uniform mat4 projection_inv_transform;

/*
 * SSAO settings
 */
// how many samples will be used for current pixel (max is 256)
uniform int u_SamplesCount;

// maximum distance of an occluder in the world space
uniform float OCCLUDER_MAX_DISTANCE = 35.5;

// if true, occluder projection will be equal to max size.
// TODO: when true, occluder max distance has to be recomputed
uniform bool USE_CONSTANT_OCCLUDER_PROJECTION = false;

// these two constants will limit how big area in image space will be sampled.
// farther areas will be smaller in size and thus will contain less samples,
// less far areas will be bigger in screen size and will be covered by more samples.
// Samples count should change with square of projected screen size?
uniform float PROJECTED_OCCLUDER_DISTANCE_MIN_SIZE = 2;
uniform float PROJECTED_OCCLUDER_DISTANCE_MAX_SIZE = 35;

// determines how big fraction of the samples will be used for the minimal computed 
// projection of occluder distance
uniform float MINIMAL_SAMPLES_COUNT_RATIO = 0.5;
uniform float STRENGTH = 0.1;
uniform float BIAS = 0.1;


////////////////////////////////////////////////////////////////////////////////
//shared storage//
shared Occluder[c_MaxOccludersCount] s_Occluders;
shared vec2 s_Rf;

////////////////////////////////////////////////////////////////////////////////
//local variables//
struct { vec2 Size; vec2 Param; vec2 GroupParam; } 
	local_Target;

vec2 local_Rf;
// P is the sample in target for which Ssao is computed by the current invocation
Sample local_P;

struct { 	vec2 RANDOMIZATION_VECTOR; 	int RANDOMIZATION_OFFSET; }
	local_Sampling;

////////////////////////////////////////////////////////////////////////////////
//utility and library functions//

//
void InitSampling()
{
	int indexA = int(gl_GlobalInvocationID.x) *  173547 + int(gl_GlobalInvocationID.y) * 364525 + 1013904223;
	indexA = (indexA >> 4) & 0xFFF;

	int indexB = int(gl_GlobalInvocationID.x) *  472541 + int(gl_GlobalInvocationID.y) * 198791 + 2103477191;
	indexB = (indexB >> 4) & 0xFFF;

	local_Sampling.RANDOMIZATION_VECTOR = vec2( cos(c_TWO_PI * (indexA * indexB)/360), sin(c_TWO_PI * (indexB * indexA)/360));
	local_Sampling.RANDOMIZATION_OFFSET = indexB * indexA;
}

//
vec2 GetSamplingPoint(int i)
{
	return reflect(u_SamplingPattern[(i * 97 + local_Sampling.RANDOMIZATION_OFFSET) % u_SamplingPattern.length()], local_Sampling.RANDOMIZATION_VECTOR);
}

//
int GetSamplingIndex(int i, int limit)
{
	return (i * 97 + local_Sampling.RANDOMIZATION_OFFSET) % limit;
}

//
vec4 GetClipCoord (vec2 param, float imagedepth)
{
	return vec4(2 * param - 1, imagedepth, 1);
}

//
vec4 Reproject (mat4 transform, vec4 vector)
{
	vec4 result = transform * vector;
	result /= result.w;
	return result;
}

//
vec4 GetNormalDepth (vec2 param)
{
	vec4 result = imageLoad(u_NormalDepth, ivec2(param * imageSize(u_NormalDepth)));
	return result * 2 - 1;
}

/*
 * screen space radius of sphere of influence (projection of its size in range -1, 1)
 */
vec2 ComputeOccludedRadiusProjection(float camera_space_dist)
{	
	//for constant projection this is important just for determining aspect ratio
	vec2 projection = Reproject(projection_transform, vec4(OCCLUDER_MAX_DISTANCE, OCCLUDER_MAX_DISTANCE, camera_space_dist, 1)).xy * 0.5;

	if(USE_CONSTANT_OCCLUDER_PROJECTION)
		return projection * PROJECTED_OCCLUDER_DISTANCE_MAX_SIZE / (local_Target.Size.x * projection.x);
	else
		return clamp(projection,
			vec2(PROJECTED_OCCLUDER_DISTANCE_MIN_SIZE / local_Target.Size.x),
	  	vec2(PROJECTED_OCCLUDER_DISTANCE_MAX_SIZE / local_Target.Size.x));
}

/*
 * compute number of samples needed (step size)
 */
int ComputeStepFromOccludedScreenSize(vec2 rf)
{
	int samplesCount = clamp(u_SamplesCount, 1, c_MaxSamplesCount);
	
	// compute projection screen size
	rf *= local_Target.Size;

	// compute number of samples needed (step size)
	float ssize = samplesCount * clamp(MINIMAL_SAMPLES_COUNT_RATIO, 0, 1);
	float msize = samplesCount * (1 - clamp(MINIMAL_SAMPLES_COUNT_RATIO, 0, 1));

	float min_dist_squared = pow(PROJECTED_OCCLUDER_DISTANCE_MIN_SIZE, 2);
	float max_dist_squared = pow(PROJECTED_OCCLUDER_DISTANCE_MAX_SIZE, 2);
	float rf_squared = pow(max(rf.x, rf.y), 2);

	// linear interpolation between (msize + ssize) and ssize, parameter is squared projection size
	float samples_cnt =
		(msize / (max_dist_squared - min_dist_squared)) *
		(rf_squared - min_dist_squared) +  ssize;

 	float step = clamp(samplesCount / samples_cnt, 1, samplesCount);
 	return int(step);
}

void InitGlobals()
{
	InitSampling();
	
	local_Target.Param = vec2(gl_GlobalInvocationID)/imageSize(u_Target);
	local_Target.Size = vec2(imageSize(u_Target));
	
	vec4 p_nd = GetNormalDepth (local_Target.Param);
	vec4 p_clip = GetClipCoord (local_Target.Param, p_nd.w);
	vec4 p_pos = Reproject (modelviewprojection_inv_transform, p_clip);
	vec4 p_campos = Reproject (projection_inv_transform, p_clip);

  local_Rf =	ComputeOccludedRadiusProjection( p_campos.z );
  local_P.CamPosition = p_campos;
  local_P.N = normalize(p_nd.xyz);
  local_P.Position = p_pos;
  
  if(gl_LocalInvocationID.xy == uvec2(0,0))
	  s_Rf = local_Rf;
}

/*
 * 
 */
void ComputeOccluders()
{
	int samplesCount = clamp(u_SamplesCount, 1, c_MaxSamplesCount);
	int occCount = clamp(samplesCount * c_OccludersGroupSize, 1, c_MaxOccludersCount);
	int occLocal = occCount / c_OccludersGroupSize;
		
	// for each sample compute occlussion estimation and add it to result
	for(int start = int(gl_LocalInvocationIndex); start < c_OccludersGroupSize; start += c_WorkGroupSize)
	for(int i = start, ii = 1; i < occCount; i += c_OccludersGroupSize, ii++)
	{
		vec2 oc_index = vec2(start % c_OccludersGroupSizeX, start / c_OccludersGroupSizeX) + gl_GlobalInvocationID.xy - gl_LocalInvocationID.xy - vec2(c_OccludersRimSize);
		vec2 oc_param = oc_index/local_Target.Size + normalize(GetSamplingPoint(i)) * s_Rf * ii / occLocal;
		vec4 o_nd = GetNormalDepth (oc_param);
		vec4 o_clip = GetClipCoord (oc_param, o_nd.w);
		vec4 o_pos = Reproject ( modelviewprojection_inv_transform, o_clip);
		float o_r =  Reproject ( projection_inv_transform, vec4(2.0 / local_Target.Size.x, 0, o_nd.w, 1)).x;

		//correction to prevent occlusion from itself or from neighbours which are on the same tangent plane
		o_pos -= o_r * vec4(o_nd.xyz, 0);
		s_Occluders[i] = Occluder(o_pos.xyz, o_r);
	}
}

/*
 * 
 */
void ComputeSsao()
{
	float result = 0;
	int samplesCount = clamp(u_SamplesCount, 1, c_MaxSamplesCount);
	int occCount = clamp(samplesCount * c_OccludersGroupSize, 1, c_MaxOccludersCount);
	int occLocal = occCount / c_OccludersGroupSize;
	int step = ComputeStepFromOccludedScreenSize(local_Rf);
	int ni = 1;
	int nii = 1;
	int locId = int(c_OccludersGroupSizeX * (gl_LocalInvocationID.y + c_OccludersRimSize) + gl_LocalInvocationID.x + c_OccludersRimSize);
	int i = locId + c_NeighbourOffsets[0];
	int si = 0;
	
	// for each sample compute occlussion estimation and add it to result
	for(; si < samplesCount; i += c_OccludersGroupSize, si += step)
	{
		if(i >= occCount)
		{
			ni = (ni + 1) % 8;
			i = locId + c_NeighbourOffsets[ni + 1] * nii;
		}
		
		const Occluder o = s_Occluders[i];
		const Sample p = local_P;

		vec3 opvec = o.Position.xyz - p.Position.xyz;
		float opdist = length (opvec);
		float omega = c_TWO_PI * (1 - cos( asin( clamp(o.Radius / opdist, 0, 1))));
		result +=
			opdist <= OCCLUDER_MAX_DISTANCE ?
				omega * max(dot(opvec, p.N) / opdist, 0):
			//else
				0;
	}

	imageStore(u_Target, ivec2(gl_GlobalInvocationID), vec4(pow(result, BIAS) * STRENGTH));
}

////////////////////////////////////////////////////////////////////////////////
//kernel//
void main ()
{
	InitGlobals();
	barrier();
	ComputeOccluders();
	barrier();
	ComputeSsao();
}
