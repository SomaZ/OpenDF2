/*[Vertex]*/
#if defined(USE_LIGHT) && !defined(USE_FAST_LIGHT)
#define PER_PIXEL_LIGHTING
#endif
in vec2 attr_TexCoord0;
#if defined(USE_LIGHTMAP) || defined(USE_TCGEN)
in vec2 attr_TexCoord1;
in vec2 attr_TexCoord2;
in vec2 attr_TexCoord3;
in vec2 attr_TexCoord4;
#endif
in vec4 attr_Color;

in vec3 attr_Position;
in vec3 attr_Normal;
in vec4 attr_Tangent;

#if defined(USE_VERTEX_ANIMATION)
in vec3 attr_Position2;
in vec3 attr_Normal2;
in vec4 attr_Tangent2;
#elif defined(USE_SKELETAL_ANIMATION)
in uvec4 attr_BoneIndexes;
in vec4 attr_BoneWeights;
#endif

#if defined(USE_LIGHT) && !defined(USE_LIGHT_VECTOR)
in vec3 attr_LightDirection;
#endif

layout(std140) uniform Camera
{
	vec4 u_ViewInfo;
	vec3 u_ViewOrigin;
	vec3 u_ViewForward;
	vec3 u_ViewLeft;
	vec3 u_ViewUp;
};

layout(std140) uniform Scene
{
	vec4 u_PrimaryLightOrigin;
	vec3 u_PrimaryLightAmbient;
	vec3 u_PrimaryLightColor;
	float u_PrimaryLightRadius;
};

layout(std140) uniform Entity
{
	mat4 u_ModelMatrix;
	mat4 u_ModelViewProjectionMatrix;
	vec4 u_LocalLightOrigin;
	vec3 u_AmbientLight;
	float u_LocalLightRadius;
	vec3 u_DirectedLight;
	float u_FXVolumetricBase;
	vec3 u_ModelLightDir;
	float u_VertexLerp;
	vec3 u_LocalViewOrigin;
};

#if defined(USE_SKELETAL_ANIMATION)
layout(std140) uniform Bones
{
	mat3x4 u_BoneMatrices[MAX_G2_BONES];
};
#endif

#if defined(USE_DELUXEMAP)
uniform vec4   u_EnableTextures; // x = normal, y = deluxe, z = specular, w = cube
#endif

#if defined(USE_TCGEN) || defined(USE_LIGHTMAP)
uniform int u_TCGen0;
uniform vec3 u_TCGen0Vector0;
uniform vec3 u_TCGen0Vector1;
uniform int u_TCGen1;
#endif

#if defined(USE_TCMOD)
uniform vec4 u_DiffuseTexMatrix;
uniform vec4 u_DiffuseTexOffTurb;
#endif

uniform vec4 u_BaseColor;
uniform vec4 u_VertColor;
uniform vec4 u_Disintegration;
uniform int u_ColorGen;

out vec4 var_TexCoords;
out vec4 var_Color;
out vec3 var_N;

#if defined(PER_PIXEL_LIGHTING)
out vec4 var_Normal;
out vec4 var_Tangent;
out vec4 var_Bitangent;
#endif

#if defined(PER_PIXEL_LIGHTING)
out vec4 var_LightDir;
#endif

#if defined(USE_PRIMARY_LIGHT) || defined(USE_SHADOWMAP)
out vec4 var_PrimaryLightDir;
#endif

vec4 CalcColor(vec3 position)
{
	vec4 color = vec4(1.0);
	if (u_ColorGen == CGEN_DISINTEGRATION_1)
	{
		vec3 delta = u_Disintegration.xyz - position;
		float sqrDistance = dot(delta, delta);
		if (sqrDistance < u_Disintegration.w)
		{
			color = vec4(0.0);
		}
		else if (sqrDistance < u_Disintegration.w + 60.0)
		{
			color = vec4(0.0, 0.0, 0.0, 1.0);
		}
		else if (sqrDistance < u_Disintegration.w + 150.0)
		{
			color = vec4(0.435295, 0.435295, 0.435295, 1.0);
		}
		else if (sqrDistance < u_Disintegration.w + 180.0)
		{
			color = vec4(0.6862745, 0.6862745, 0.6862745, 1.0);
		}
		return color;
	}
	else if (u_ColorGen == CGEN_DISINTEGRATION_2)
	{
		vec3 delta = u_Disintegration.xyz - position;
		float sqrDistance = dot(delta, delta);
		if (sqrDistance < u_Disintegration.w)
		{
			return vec4(0.0);
		}
		return color;
	}
	return color;
}

#if defined(USE_TCGEN) || defined(USE_LIGHTMAP)
vec2 GenTexCoords(int TCGen, vec3 position, vec3 normal, vec3 TCGenVector0, vec3 TCGenVector1)
{
	vec2 tex = attr_TexCoord0;

	switch (TCGen)
	{
		case TCGEN_LIGHTMAP:
			tex = attr_TexCoord1;
		break;

		case TCGEN_LIGHTMAP1:
			tex = attr_TexCoord2;
		break;

		case TCGEN_LIGHTMAP2:
			tex = attr_TexCoord3;
		break;

		case TCGEN_LIGHTMAP3:
			tex = attr_TexCoord4;
		break;

		case TCGEN_ENVIRONMENT_MAPPED:
		{
			vec3 viewer = normalize(u_LocalViewOrigin - position);
			vec2 ref = reflect(viewer, normal).yz;
			tex.s = ref.x * -0.5 + 0.5;
			tex.t = ref.y *  0.5 + 0.5;
		}
		break;

		case TCGEN_VECTOR:
		{
			tex = vec2(dot(position, TCGenVector0), dot(position, TCGenVector1));
		}
		break;
	}

	return tex;
}
#endif

#if defined(USE_TCMOD)
vec2 ModTexCoords(vec2 st, vec3 position, vec4 texMatrix, vec4 offTurb)
{
	float amplitude = offTurb.z;
	float phase = offTurb.w * 2.0 * M_PI;
	vec2 st2;
	st2.x = st.x * texMatrix.x + (st.y * texMatrix.z + offTurb.x);
	st2.y = st.x * texMatrix.y + (st.y * texMatrix.w + offTurb.y);

	vec2 offsetPos = vec2(position.x + position.z, position.y);

	vec2 texOffset = sin(offsetPos * (2.0 * M_PI / 1024.0) + vec2(phase));

	return st2 + texOffset * amplitude;	
}
#endif


float CalcLightAttenuation(in bool isPoint, float normDist)
{
	// zero light at 1.0, approximating q3 style
	// also don't attenuate directional light
	float attenuation = 1.0 + mix(0.0, 0.5 * normDist - 1.5, isPoint);
	return clamp(attenuation, 0.0, 1.0);
}

#if defined(USE_SKELETAL_ANIMATION)
mat4x3 GetBoneMatrix(uint index)
{
	mat3x4 bone = u_BoneMatrices[index];
	return mat4x3(
		bone[0].x, bone[1].x, bone[2].x,
		bone[0].y, bone[1].y, bone[2].y,
		bone[0].z, bone[1].z, bone[2].z,
		bone[0].w, bone[1].w, bone[2].w);
}
#endif

void main()
{
#if defined(USE_VERTEX_ANIMATION)
	vec3 position  = mix(attr_Position,    attr_Position2,    u_VertexLerp);
	vec3 normal    = mix(attr_Normal,      attr_Normal2,      u_VertexLerp);
	vec3 tangent   = mix(attr_Tangent.xyz, attr_Tangent2.xyz, u_VertexLerp);
#elif defined(USE_SKELETAL_ANIMATION)
	mat4x3 influence =
		GetBoneMatrix(attr_BoneIndexes[0]) * attr_BoneWeights[0] +
        GetBoneMatrix(attr_BoneIndexes[1]) * attr_BoneWeights[1] +
        GetBoneMatrix(attr_BoneIndexes[2]) * attr_BoneWeights[2] +
        GetBoneMatrix(attr_BoneIndexes[3]) * attr_BoneWeights[3];

    vec3 position = influence * vec4(attr_Position, 1.0);
    vec3 normal = normalize(influence * vec4(attr_Normal - vec3(0.5), 0.0));
	#if defined(PER_PIXEL_LIGHTING)
		vec3 tangent = normalize(influence * vec4(attr_Tangent.xyz - vec3(0.5), 0.0));
	#endif
#else
	vec3 position  = attr_Position;
	vec3 normal    = attr_Normal;
  #if defined(PER_PIXEL_LIGHTING)
	vec3 tangent   = attr_Tangent.xyz;
  #endif
#endif

#if !defined(USE_SKELETAL_ANIMATION)
	normal  = normal  * 2.0 - vec3(1.0);
  #if defined(PER_PIXEL_LIGHTING)
	tangent = tangent * 2.0 - vec3(1.0);
  #endif
#endif

#if defined(USE_TCGEN)
	vec2 texCoords = GenTexCoords(u_TCGen0, position, normal, u_TCGen0Vector0, u_TCGen0Vector1);
#else
	vec2 texCoords = attr_TexCoord0.st;
#endif

#if defined(USE_TCMOD)
	var_TexCoords.xy = ModTexCoords(texCoords, position, u_DiffuseTexMatrix, u_DiffuseTexOffTurb);
#else
	var_TexCoords.xy = texCoords;
#endif

	vec4 disintegration = CalcColor(position);

	gl_Position = u_ModelViewProjectionMatrix * vec4(position, 1.0);

	position  = (u_ModelMatrix * vec4(position, 1.0)).xyz;
	normal    = (u_ModelMatrix * vec4(normal,   0.0)).xyz;
  #if defined(PER_PIXEL_LIGHTING)
	tangent   = (u_ModelMatrix * vec4(tangent,  0.0)).xyz;
  #endif

#if defined(PER_PIXEL_LIGHTING)
	vec3 bitangent = cross(normal, tangent) * (attr_Tangent.w * 2.0 - 1.0);
#endif

#if defined(USE_LIGHT_VECTOR)
	vec3 L = u_LocalLightOrigin.xyz - (position * u_LocalLightOrigin.w);
#elif defined(PER_PIXEL_LIGHTING)
	vec3 L = attr_LightDirection * 2.0 - vec3(1.0);
	L = (u_ModelMatrix * vec4(L, 0.0)).xyz;
#endif

#if defined(USE_LIGHTMAP)
	var_TexCoords.zw = GenTexCoords(u_TCGen1, vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0));
#endif

	if ( u_FXVolumetricBase > 0.0 )
	{
		vec3 viewForward = u_ViewForward.xyz;

		float d = clamp(dot(normalize(viewForward), normalize(normal)), 0.0, 1.0);
		d = d * d;
		d = d * d;

		var_Color = vec4(u_FXVolumetricBase * (1.0 - d));
	}
	else
	{
		var_Color = u_VertColor * attr_Color + u_BaseColor;

		#if defined(USE_LIGHT_VECTOR) && defined(USE_FAST_LIGHT)
		float sqrLightDist = dot(L, L);
		float attenuation = CalcLightAttenuation(u_LocalLightOrigin.w, u_LightRadius * u_LightRadius / sqrLightDist);
		float NL = clamp(dot(normalize(normal), L) / sqrt(sqrLightDist), 0.0, 1.0);

		var_Color.rgb *= u_DirectedLight * (attenuation * NL) + u_AmbientLight;
#endif
	}
	var_Color *= disintegration;

#if defined(USE_PRIMARY_LIGHT) || defined(USE_SHADOWMAP)
	var_PrimaryLightDir.xyz = u_PrimaryLightOrigin.xyz - (position * u_PrimaryLightOrigin.w);
	var_PrimaryLightDir.w = u_PrimaryLightRadius * u_PrimaryLightRadius;
#endif

#if defined(PER_PIXEL_LIGHTING)
  var_LightDir = vec4(L, 0.0);
  #if defined(USE_DELUXEMAP)
	var_LightDir -= u_EnableTextures.y * var_LightDir;
  #endif
#endif

#if defined(PER_PIXEL_LIGHTING)
	vec3 viewDir = u_ViewOrigin.xyz - position;

	// store view direction in tangent space to save on outs
	var_Normal    = vec4(normal,    viewDir.x);
	var_Tangent   = vec4(tangent,   viewDir.y);
	var_Bitangent = vec4(bitangent, viewDir.z);
#endif
}

/*[Fragment]*/
#if defined(USE_LIGHT) && !defined(USE_VERTEX_LIGHTING)
#define PER_PIXEL_LIGHTING
#endif
layout(std140) uniform Scene
{
	vec4 u_PrimaryLightOrigin;
	vec3 u_PrimaryLightAmbient;
	vec3 u_PrimaryLightColor;
	float u_PrimaryLightRadius;
};

layout(std140) uniform Camera
{
	vec4 u_ViewInfo;
	vec3 u_ViewOrigin;
	vec3 u_ViewForward;
	vec3 u_ViewLeft;
	vec3 u_ViewUp;
};

layout(std140) uniform Entity
{
	mat4 u_ModelMatrix;
	mat4 u_ModelViewProjectionMatrix;
	vec4 u_LocalLightOrigin;
	vec3 u_AmbientLight;
	float u_LocalLightRadius;
	vec3 u_DirectedLight;
	float u_FXVolumetricBase;
	vec3 u_ModelLightDir;
	float u_VertexLerp;
	vec3 u_LocalViewOrigin;
};

struct Light
{
	vec4 origin;
	vec3 color;
	float radius;
};

layout(std140) uniform Lights
{
	int u_NumLights;
	Light u_Lights[32];
};

uniform int u_LightIndex;
uniform sampler2D u_DiffuseMap;

#if defined(USE_LIGHTMAP)
uniform sampler2D u_LightMap;
#endif

#if defined(USE_NORMALMAP)
uniform sampler2D u_NormalMap;
#endif

#if defined(USE_DELUXEMAP)
uniform sampler2D u_DeluxeMap;
#endif

#if defined(USE_SPECULARMAP)
uniform sampler2D u_SpecularMap;
#endif

#if defined(USE_SHADOWMAP)
uniform sampler2D u_ShadowMap;
#endif

//uniform samplerCubeShadow u_ShadowMap2;

#if defined(USE_CUBEMAP)
uniform samplerCube u_CubeMap;
uniform sampler2D u_EnvBrdfMap;
#endif

#if defined(USE_NORMALMAP) || defined(USE_DELUXEMAP) || defined(USE_SPECULARMAP) || defined(USE_CUBEMAP)
// y = deluxe, w = cube
uniform vec4 u_EnableTextures;
#endif

uniform vec4 u_NormalScale;
uniform vec4 u_SpecularScale;
uniform float u_ParallaxBias;

#if defined(PER_PIXEL_LIGHTING) && defined(USE_CUBEMAP)
uniform vec4 u_CubeMapInfo;
#endif

#if defined(USE_ALPHA_TEST)
uniform int u_AlphaTestType;
#endif


in vec4 var_TexCoords;
in vec4 var_Color;

#if defined(PER_PIXEL_LIGHTING)
in vec4 var_Normal;
in vec4 var_Tangent;
in vec4 var_Bitangent;
in vec4 var_LightDir;
#endif

#if defined(USE_PRIMARY_LIGHT) || defined(USE_SHADOWMAP)
in vec4 var_PrimaryLightDir;
#endif

out vec4 out_Color;
out vec4 out_Glow;

#define EPSILON 0.00000001

#if defined(USE_PARALLAXMAP)
float SampleDepth(sampler2D normalMap, vec2 t)
{
	return 1.0 - texture(normalMap, t).r;
}

float RayIntersectDisplaceMap(in vec2 inDp, in vec2 ds, in sampler2D normalMap, in float parallaxBias)
{
	const int linearSearchSteps = 16;
	const int binarySearchSteps = 4;

	vec2 dp = inDp - parallaxBias * ds;

	// current size of search window
	float size = 1.0 / float(linearSearchSteps);

	// current depth position
	float depth = 0.0;

	// best match found (starts with last position 1.0)
	float bestDepth = 1.0;

	// search front to back for first point inside object
	for(int i = 0; i < linearSearchSteps - 1; ++i)
	{
		depth += size;
		
		float t = SampleDepth(normalMap, dp + ds * depth);
		
		if(bestDepth > 0.996)		// if no depth found yet
			if(depth >= t)
				bestDepth = depth;	// store best depth
	}

	depth = bestDepth;
	
	// recurse around first point (depth) for closest match
	for(int i = 0; i < binarySearchSteps; ++i)
	{
		size *= 0.5;

		float t = SampleDepth(normalMap, dp + ds * depth);
		
		if(depth >= t)
		{
			bestDepth = depth;
			depth -= 2.0 * size;
		}

		depth += size;
	}

	vec2 prevTexCoords = dp + ds * (depth-size);
	float afterDepth  = SampleDepth(normalMap, dp + ds * depth) - depth;
	float beforeDepth = SampleDepth(normalMap, prevTexCoords) - depth + size;
	float weight = afterDepth / (afterDepth - beforeDepth);
	bestDepth -= weight*size;

	return bestDepth - parallaxBias;
}
#endif

float D_Charlie(in float a, in float NH)
{
	// Estevez and Kulla 2017, "Production Friendly Microfacet Sheen BRDF"
	float invAlpha = 1.0 / a;
	float cos2h = NH * NH;
	float sin2h = max(1.0 - cos2h, 0.0078125); // 2^(-14/2), so sin2h^2 > 0 in fp16
	return (2.0 + invAlpha) * pow(sin2h, invAlpha * 0.5) / (2.0 * M_PI);
}

float V_Neubelt(in float NV, in float NL)
{
	// Neubelt and Pettineo 2013, "Crafting a Next-gen Material Pipeline for The Order: 1886"
	return 1.0 / (4.0 * (NL + NV - NL * NV));
}

float D_Ashikhmin(float roughness, float nh){
                float a2 = roughness * roughness;
                float cos2h = nh * nh ;
                float sin2h = max(1.0 - cos2h, 0.0078125); // 2^(-14/2), so sin2h^2 > 0 in fp16
	            float sin4h = sin2h * sin2h;
                float cot2 = -cos2h / (a2 * sin2h);
	            return 1.0 / (M_PI * (4.0 * a2 + 1.0) * sin4h) * (4.0 * exp(cot2) + sin4h);

            }

vec3 Specular_CharlieSheen(float Roughness, float NoH, float NoV, float NoL, vec3 SpecularColor, float cloth)
{
	float D = cloth > 0.f ? D_Ashikhmin(Roughness, NoH) : D_Charlie(Roughness, NoH);

	return (D * V_Neubelt(NoV, NoL)) * SpecularColor; //No fresnel in the documentation.
}

vec3 Fresnel_Schlick(const vec3 f0, float f90, float VoH)
{
	// Schlick 1994, "An Inexpensive BRDF Model for Physically-Based Rendering"
	return f0 + (f90 - f0) * pow(1.0 - VoH, 5.f);
}

vec3 Diff_Burley(float roughness, float NoV, float NoL, float LoH)
{
	// Burley 2012, "Physically-Based Shading at Disney"
	float f90 = 0.5 + 2.0 * roughness * LoH * LoH;
	vec3 lightScatter = Fresnel_Schlick(vec3(1.0), f90, NoL);
	vec3 viewScatter = Fresnel_Schlick(vec3(1.0), f90, NoV);
	return lightScatter * viewScatter * (1.0 / M_PI);
}

vec3 F_Schlick(in vec3 SpecularColor, in float VH)
{
	float Fc = pow(1 - VH, 5);
	return clamp(50.0 * SpecularColor.g, 0.0, 1.0) * Fc + (1 - Fc) * SpecularColor; //hacky way to decide if reflectivity is too low (< 2%)
}

float D_GGX( in float NH, in float a )
{
	/*float alphaSq = roughness*roughness;
	float f = (NH * alphaSq - NH) * NH + 1.0;
	return alphaSq / (f * f);*/

	float a2 = a * a;
	float d = (NH * a2 - NH) * NH + 1;
	return a2 / (M_PI * d * d);
}

// Appoximation of joint Smith term for GGX
// [Heitz 2014, "Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs"]
float V_SmithJointApprox(in float a, in float NV, in float NL)
{
	float Vis_SmithV = NL * (NV * (1 - a) + a);
	float Vis_SmithL = NV * (NL * (1 - a) + a);
	return 0.5 * (1.0 / (Vis_SmithV + Vis_SmithL));
}

float CalcVisibility(in float NL, in float NE, in float roughness)
{
	float alphaSq = roughness * roughness;

	float lambdaE = NL * sqrt((-NE * alphaSq + NE) * NE + alphaSq);
	float lambdaL = NE * sqrt((-NL * alphaSq + NL) * NL + alphaSq);

	return 0.5 / (lambdaE + lambdaL);
}

// http://www.frostbite.com/2014/11/moving-frostbite-to-pbr/
vec3 CalcSpecular(
	in vec3 specular,
	in float NH,
	in float NL,
	in float NE,
	in float LH,
	in float VH,
	in float roughness
)
{
	//Using #if to define our BRDF's is a good idea.
#if !defined(USE_CLOTH_BRDF) //should define this as the base BRDF
	vec3  F = F_Schlick(specular, VH);
	float D = D_GGX(NH, roughness);
	float V = V_SmithJointApprox(roughness, NE, NL);
#else //and define this as the cloth BRDF
	//this cloth model essentially uses the metallic input to help transition from isotropic to anisotropic reflections.
	//as cloth is a microfibre structure, cloth like velevet and silk tends to have anisotropy.
	vec3 F = specular; //this shading model omits fresnel
	float D = D_Charlie(roughness, NH);
	float V = V_Neubelt(NE, NL);
#endif

	return D * F * V;
}

//Energy conserving wrap term.
float WrapLambert(in float NL, in float w)
{
	return clamp((NL + w) / pow(1.0 + w, 2), 0.0, 1.0);
}

vec3 Diffuse_Lambert(in vec3 DiffuseColor)
{
	return DiffuseColor * (1.0 / M_PI);
}

vec3 CalcDiffuse(
	in vec3 diffuse,
	in float NE,
	in float NL,
	in float LH,
	in float roughness
)
{
	//Using #if to define our diffuse's is a good idea.
#if !defined(USE_CLOTH_BRDF) //should define this as the base BRDF
	return Diffuse_Lambert(diffuse);
#else //and define this as the cloth diffuse
	//this cloth model has a wrapped diffuse, we can be energy conservant here.
	vec3 d = Diffuse_Lambert(diffuse);
	d *= WrapLambert(NL, 0.5);
	// Cheap subsurface scatter
	// ideally we should actually have a new colour for subsurface, but for cloth most times it makes sense to just use the diffuse.
	d *= clamp(diffuse + NL, 0.0, 1.0);
	return d;
#endif
}

float CalcLightAttenuation(float point, float normDist)
{
	// zero light at 1.0, approximating q3 style
	// also don't attenuate directional light
	float attenuation = (0.5 * normDist - 1.5) * point + 1.0;
	return clamp(attenuation, 0.0, 1.0);
}

#if defined(USE_LIGHT_VECTOR) && !defined(USE_VERTEX_LIGHTING) && defined(USE_DSHADOWS)
#define DEPTH_MAX_ERROR 0.000000059604644775390625

vec3 sampleOffsetDirections[20] = vec3[]
(
	vec3(1.0, 1.0, 1.0), vec3(1.0, -1.0, 1.0), vec3(-1.0, -1.0, 1.0), vec3(-1.0, 1.0, 1.0),
	vec3(1.0, 1.0, -1.0), vec3(1.0, -1.0, -1.0), vec3(-1.0, -1.0, -1.0), vec3(-1.0, 1.0, -1.0),
	vec3(1.0, 1.0, 0.0), vec3(1.0, -1.0, 0.0), vec3(-1.0, -1.0, 0.0), vec3(-1.0, 1.0, 0.0),
	vec3(1.0, 0.0, 1.0), vec3(-1.0, 0.0, 1.0), vec3(1.0, 0.0, -1.0), vec3(-1.0, 0.0, -1.0),
	vec3(0.0, 1.0, 1.0), vec3(0.0, -1.0, 1.0), vec3(0.0, -1.0, -1.0), vec3(0.0, 1.0, -1.0)
	);

float pcfShadow(in samplerCubeShadow depthMap, in vec3 L, in float distance)
{
	float shadow = 0.0;
	int samples = 20;
	float diskRadius = 0.25;
	for (int i = 0; i < samples; ++i)
	{
		shadow += texture(depthMap, vec4(L + sampleOffsetDirections[i] * diskRadius, distance));
	}
	shadow /= float(samples);
	return shadow;
}

float getLightDepth(in vec3 Vec, in float f)
{
	vec3 AbsVec = abs(Vec);
	float Z = max(AbsVec.x, max(AbsVec.y, AbsVec.z));

	const float n = 1.0;

	float NormZComp = (f + n) / (f - n) - 2 * f*n / (Z* (f - n));

	return ((NormZComp + 1.0) * 0.5) - DEPTH_MAX_ERROR;
}

float getShadowValue(in vec4 light)
{
	float distance = getLightDepth(light.xyz, sqrt(light.w));
	//return pcfShadow(u_ShadowMap2, light.xyz, distance);
	return 1.0;
}
#endif

vec2 GetParallaxOffset(in vec2 texCoords, in vec3 E, in mat3 tangentToWorld )
{
#if defined(USE_PARALLAXMAP)
	vec3 offsetDir = normalize(E * tangentToWorld);
	offsetDir.xy *= -u_NormalScale.a / offsetDir.z;

	return offsetDir.xy * RayIntersectDisplaceMap(texCoords, offsetDir.xy, u_NormalMap, u_ParallaxBias);
#else
	return vec2(0.0);
#endif
}

vec3 CalcDynamicLightContribution(
	in float roughness,
	in vec3 N,
	in vec3 E,
	in vec3 viewOrigin,
	in vec3 viewDir,
	in float NE,
	in vec3 diffuse,
	in vec3 specular
)
{
	vec3 outColor = vec3(0.0);
	vec3 position = viewOrigin - viewDir;
	for ( int i = 0; i < u_NumLights; i++ )
	{
		if ( ( u_LightIndex & ( 1 << i ) ) == 0 ) {
			continue;
		}
		Light light = u_Lights[i];
		
		vec3  L  = light.origin.xyz - position;
		float sqrLightDist = dot(L, L);

		float attenuation = CalcLightAttenuation(1.0, light.radius * light.radius / sqrLightDist);

		L /= sqrt(sqrLightDist);
		vec3  H  = normalize(L + E);
		float NL = clamp(dot(N, L), 0.0, 1.0);
		float LH = clamp(dot(L, H), 0.0, 1.0);
		float NH = clamp(dot(N, H), 0.0, 1.0);
		float VH = clamp(dot(E, H), 0.0, 1.0);

		vec3 reflectance = diffuse + CalcSpecular(specular, NH, NL, NE, LH, VH, roughness);

		outColor += light.color * reflectance * attenuation * NL;
	}
	return outColor;
}

vec3 CalcIBLContribution(
	in float roughness,
	in vec3 N,
	in vec3 E,
	in vec3 viewOrigin,
	in vec3 viewDir,
	in float NE,
	in vec3 specular
)
{
#if defined(PER_PIXEL_LIGHTING) &&  defined(USE_CUBEMAP)
	vec3 R = reflect(-E, N);

	// parallax corrected cubemap (cheaper trick)
	// from http://seblagarde.wordpress.com/2012/09/29/image-based-lighting-approaches-and-parallax-corrected-cubemap/
	vec3 parallax = u_CubeMapInfo.xyz + u_CubeMapInfo.w * viewDir;
	vec3 cubeLightColor = textureLod(u_CubeMap, R - parallax, roughness * ROUGHNESS_MIPS).rgb * u_EnableTextures.w;

	#if !defined(USE_CLOTH_BRDF) //should define this as the base BRDF
		vec2 EnvBRDF = texture(u_EnvBrdfMap, vec2(roughness, NE)).rg;
		return cubeLightColor * (specular.rgb * EnvBRDF.x + EnvBRDF.y);
	#else //and define this as the cloth brdf
		float EnvBRDF = texture(u_EnvBrdfMap, vec2(roughness, NE)).b;
		return cubeLightColor * EnvBRDF;
	#endif
#else
	return vec3(0.0);
#endif
}

vec3 CalcNormal( in vec3 vertexNormal, in vec2 texCoords, in mat3 tangentToWorld )
{
	vec3 N = vertexNormal;

#if defined(USE_NORMALMAP)
	N.xy = texture(u_NormalMap, texCoords).ag - vec2(0.5);
	N.xy *= u_NormalScale.xy;
	N.z = sqrt(clamp((0.25 - N.x * N.x) - N.y * N.y, 0.0, 1.0));
	N = tangentToWorld * N;
#endif

	return normalize(N);
}

void main()
{
	vec3 viewDir, lightColor, ambientColor;
	vec3 L, N, E;

#if defined(PER_PIXEL_LIGHTING)
	mat3 tangentToWorld = mat3(var_Tangent.xyz, var_Bitangent.xyz, var_Normal.xyz);
	viewDir = vec3(var_Normal.w, var_Tangent.w, var_Bitangent.w);
	E = normalize(viewDir);
	L = var_LightDir.xyz;
  #if defined(USE_DELUXEMAP)
	L += (texture(u_DeluxeMap, var_TexCoords.zw).xyz - vec3(0.5)) * u_EnableTextures.y;
  #endif
	float sqrLightDist = dot(L, L);
#endif

#if defined(USE_LIGHTMAP)
	vec4 lightmapColor = texture(u_LightMap, var_TexCoords.zw);
#endif

	vec2 texCoords = var_TexCoords.xy;
#if defined(PER_PIXEL_LIGHTING)
	texCoords += GetParallaxOffset(texCoords, E, tangentToWorld);
#endif

	vec4 diffuse = texture(u_DiffuseMap, texCoords);
	diffuse.a *= var_Color.a;
#if defined(USE_ALPHA_TEST)
	if (u_AlphaTestType == ALPHA_TEST_GT0)
	{
		if (diffuse.a == 0.0)
			discard;
	}
	else if (u_AlphaTestType == ALPHA_TEST_LT128)
	{
		if (diffuse.a >= 0.5)
			discard;
	}
	else if (u_AlphaTestType == ALPHA_TEST_GE128)
	{
		if (diffuse.a < 0.5)
			discard;
	}
	else if (u_AlphaTestType == ALPHA_TEST_GE192)
	{
		if (diffuse.a < 0.75)
			discard;
	}
#endif

#if defined(PER_PIXEL_LIGHTING)
	float attenuation;

  #if defined(USE_LIGHTMAP)
	lightColor	= lightmapColor.rgb * var_Color.rgb;
	ambientColor = vec3 (0.0);
	attenuation = 1.0;
  #elif defined(USE_LIGHT_VECTOR)
	lightColor	= u_DirectedLight * var_Color.rgb;
	ambientColor = u_AmbientLight * var_Color.rgb;
	attenuation = CalcLightAttenuation(float(var_LightDir.w > 0.0), var_LightDir.w / sqrLightDist);

    #if defined(USE_DSHADOWS)
	  if (var_LightDir.w > 0.0) {
	    attenuation *= getShadowValue(var_LightDir);
	  }
    #endif

  #elif defined(USE_LIGHT_VERTEX)
	lightColor	= var_Color.rgb;
	ambientColor = vec3 (0.0);
	attenuation = 1.0;
  #endif

	N = CalcNormal(var_Normal.xyz, texCoords, tangentToWorld);
	L /= sqrt(sqrLightDist);

  #if defined(USE_SHADOWMAP)
	vec2 shadowTex = gl_FragCoord.xy * r_FBufScale;
	float shadowValue = texture(u_ShadowMap, shadowTex).r;

	// surfaces not facing the light are always shadowed
	vec3 primaryLightDir = normalize(var_PrimaryLightDir.xyz);
	shadowValue = mix(0.0, shadowValue, dot(N, primaryLightDir) > 0.0);

    #if defined(SHADOWMAP_MODULATE)
	lightColor = mix(u_PrimaryLightAmbient * lightColor, lightColor, shadowValue);
    #endif
  #endif

  #if defined(USE_LIGHTMAP) || defined(USE_LIGHT_VERTEX)
	ambientColor = lightColor;
	float surfNL = clamp(dot(var_Normal.xyz, L), 0.0, 1.0);

	// Scale the incoming light to compensate for the baked-in light angle
	// attenuation.
	lightColor /= max(surfNL, 0.25);

	// Recover any unused light as ambient, in case attenuation is over 4x or
	// light is below the surface
	ambientColor = clamp(ambientColor - lightColor * surfNL, 0.0, 1.0);
  #endif
	lightColor *= M_PI;
	ambientColor *= M_PI;

	vec4 specular = vec4(1.0);
  #if defined(USE_SPECULARMAP)
	specular = texture(u_SpecularMap, texCoords);
  #endif
	specular *= u_SpecularScale;

	// energy conservation
	diffuse.rgb *= vec3(1.0) - specular.rgb;
	float roughness = mix(1.0, 0.01, specular.a);

	vec3  H  = normalize(L + E);
	float NE = abs(dot(N, E)) + 1e-5;
	float NL = clamp(dot(N, L), 0.0, 1.0);
	float LH = clamp(dot(L, H), 0.0, 1.0);

	vec3  Fd = CalcDiffuse(diffuse.rgb, NE, NL, LH, roughness);
	vec3  Fs = vec3(0.0);

  #if defined(USE_LIGHT_VECTOR)
	float NH = clamp(dot(N, H), 0.0, 1.0);
	float VH = clamp(dot(E, H), 0.0, 1.0);
	Fs = CalcSpecular(specular.rgb, NH, NL, NE, LH, VH, roughness);
  #endif

  #if (defined(USE_LIGHTMAP) && defined(USE_DELUXEMAP) && defined(r_deluxeSpecular)) || defined(USE_LIGHT_VERTEX)
	float NH = clamp(dot(N, H), 0.0, 1.0);
	float VH = clamp(dot(E, H), 0.0, 1.0);
	Fs = CalcSpecular(specular.rgb, NH, NL, NE, LH, VH, roughness) * r_deluxeSpecular;
  #endif

	vec3 reflectance = Fd + Fs;

	out_Color.rgb  = lightColor * reflectance * (attenuation * NL);
	out_Color.rgb += ambientColor * diffuse.rgb;
	
  #if defined(USE_PRIMARY_LIGHT)
	vec3  L2   = normalize(var_PrimaryLightDir.xyz);
	vec3  H2   = normalize(L2 + E);
	float NL2  = clamp(dot(N,  L2), 0.0, 1.0);
	float L2H2 = clamp(dot(L2, H2), 0.0, 1.0);
	float NH2  = clamp(dot(N,  H2), 0.0, 1.0);
	float VH2  = clamp(dot(E, H), 0.0, 1.0);
	reflectance  = CalcDiffuse(diffuse.rgb, NE, NL2, L2H2, roughness);
	reflectance += CalcSpecular(specular.rgb, NH2, NL2, NE, L2H2, VH2, roughness);

	lightColor = u_PrimaryLightColor * var_Color.rgb;
    #if defined(USE_SHADOWMAP)
	lightColor *= shadowValue;
    #endif

	out_Color.rgb += lightColor * reflectance * NL2;
  #endif
	
	out_Color.rgb += CalcDynamicLightContribution(roughness, N, E, u_ViewOrigin, viewDir, NE, diffuse.rgb, specular.rgb);
	out_Color.rgb += CalcIBLContribution(roughness, N, E, u_ViewOrigin, viewDir, NE, specular.rgb);

#else
	lightColor = var_Color.rgb;
  #if defined(USE_LIGHTMAP) 
	lightColor *= lightmapColor.rgb;
  #endif

    out_Color.rgb = diffuse.rgb * lightColor;
#endif
	
	out_Color.a = diffuse.a;

#if defined(USE_GLOW_BUFFER)
	out_Glow = out_Color;
#else
	out_Glow = vec4(0.0, 0.0, 0.0, out_Color.a);
#endif
}
