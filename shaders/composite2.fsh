#version 130
#pragma optimize(on)

uniform sampler2D gdepth;
uniform sampler2D gcolor;
uniform sampler2D gnormal;
uniform sampler2D composite;
uniform sampler2D gaux2;
uniform sampler2D gaux3;
uniform sampler2D depthtex0;
uniform sampler2D shadowtex1;
uniform sampler2D noisetex;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjection;

uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

uniform vec3 shadowLightPosition;
vec3 lightPosition = normalize(shadowLightPosition);
uniform vec3 cameraPosition;
uniform vec3 skyColor;

uniform float viewWidth;
uniform float viewHeight;
uniform float far;
uniform float frameTimeCounter;

uniform bool isEyeInWater;

uniform ivec2 eyeBrightnessSmooth;

in vec2 texcoord;
flat in vec3 suncolor;
flat in float extShadow;

const float PI = 3.14159;
const float hPI = PI / 2;

#define saturate(x) clamp(0.0,x,1.0)

vec3 normalDecode(vec2 enc) {
	vec4 nn = vec4(2.0 * enc - 1.0, 1.0, -1.0);
	float l = dot(nn.xyz,-nn.xyw);
	nn.z = l;
	nn.xy *= sqrt(l);
	return normalize(nn.xyz * 2.0 + vec3(0.0, 0.0, -1.0));
}

float flag;
vec3 color = texture(gcolor, texcoord).rgb;
vec4 vpos = vec4(texture(gdepth, texcoord).xyz, 1.0);
vec3 wpos = (gbufferModelViewInverse * vpos).xyz;
lowp vec3 wnormal;
lowp vec3 normal;
float cdepth = length(wpos);
float dFar = 1.0 / far;
float cdepthN = cdepth * dFar;

const int shadowMapResolution = 1512; // [1024 1512 2048]

const vec2 circle_offsets[25] = vec2[25](
	vec2(-0.48946f,-0.35868f),
	vec2(-0.17172f, 0.62722f),
	vec2(-0.47095f,-0.01774f),
	vec2(-0.99106f, 0.03832f),
	vec2(-0.21013f, 0.20347f),
	vec2(-0.78895f,-0.56715f),
	vec2(-0.10378f,-0.15832f),
	vec2(-0.57284f, 0.3417f ),
	vec2(-0.18633f, 0.5698f ),
	vec2( 0.35618f, 0.00714f),
	vec2( 0.28683f,-0.54632f),
	vec2(-0.4641f ,-0.88041f),
	vec2( 0.19694f, 0.6237f ),
	vec2( 0.69991f, 0.6357f ),
	vec2(-0.34625f, 0.89663f),
	vec2( 0.1726f , 0.28329f),
	vec2( 0.41492f, 0.8816f ),
	vec2( 0.1369f ,-0.97162f),
	vec2(-0.6272f , 0.67213f),
	vec2(-0.8974f , 0.42719f),
	vec2( 0.55519f, 0.32407f),
	vec2( 0.94871f, 0.26051f),
	vec2( 0.71401f,-0.3126f ),
	vec2( 0.04403f, 0.93637f),
	vec2( 0.62031f,-0.66735f)
);
const float circle_count = 25.0;

float luma(vec3 color) {
	return dot(color,vec3(0.2126, 0.7152, 0.0722));
}

#define SHADOW_MAP_BIAS 0.9
float shadowTexSmooth(in sampler2D s, in vec2 texc, float spos) {
	vec2 pix_size = vec2(1.0) / (shadowMapResolution);
	float res = 0.0;

	ivec2 px0 = ivec2((texc + pix_size * vec2(0.1, 0.5)) * shadowMapResolution);
	float bias = cdepthN * 0.005;
	float texel = texelFetch(s, px0, 0).x;
	res += float(texel + bias < spos);
	ivec2 px1 = ivec2((texc + pix_size * vec2(0.5, -0.1)) * shadowMapResolution);
	texel = texelFetch(s, px1, 0).x;
	res += float(texel + bias < spos);
	ivec2 px2 = ivec2((texc + pix_size * vec2(-0.1, -0.5)) * shadowMapResolution);
	texel = texelFetch(s, px2, 0).x;
	res += float(texel + bias < spos);
	ivec2 px3 = ivec2((texc + pix_size * vec2(0.5, 0.1)) * shadowMapResolution);
	texel = texelFetch(s, px3, 0).x;
	res += float(texel + bias < spos);

	return res * 0.25;
}

bool is_plant;

#define CAUSTIC
#ifdef CAUSTIC
#define n(p) sin(texture2D(noisetex, fract(p)).x * 2.0 * PI)
float getwave(in vec3 pos){
	float speed = 0.6;

	float t = frameTimeCounter * speed;

	vec3 p = pos / (64 + 32);
	vec2 c = p.xz;

	c.x -= t / 128;

	float wave = n(c * vec2(2.00, 1.00) + vec2(c.y * 0.2, c.x * 2.0));	c /= 6;	c.x -= t / 256;	c.y += t / (128 + 64) * 1.25;
	wave += n(c * vec2(1.75, 1.50) + vec2(c.y * 0.4, c.x * 1.8));	c.y /= 4; c.x /= 2; c.xy -= t / (256 - 64) * 0.5;
	wave += n(c * vec2(1.50, 2.00) + vec2(c.y * 0.8, c.x * 1.4));

	return wave * wave * 0.5;
}

vec3 get_water_normal(in vec3 wwpos, in vec3 displacement) {
	vec3 w1 = vec3(0.1, getwave(wwpos + vec3(0.1, 0.0, 0.0)), 0.0);
	vec3 w2 = vec3(0.0, getwave(wwpos + vec3(0.0, 0.0, 0.1)), 0.1);
	vec3 w0 = displacement;
	#define tangent w1 - w0
	#define bitangent w2 - w0
	return normalize(cross(bitangent, tangent));
}
#endif

#define SHADOW_FILTER
float shadow_map() {
	if (cdepthN > 0.9f)
		return 0.0f;
	float angle = dot(lightPosition, normal);
	float shade = 0.0;
	if (angle <= 0.05f && !is_plant) {
		shade = 1.0f;
	} else {
		vec4 shadowposition = shadowModelView * vec4(wpos + normal * 0.025f, 1.0f);
		shadowposition = shadowProjection * shadowposition;
		float distb = sqrt(shadowposition.x * shadowposition.x + shadowposition.y * shadowposition.y);
		float distortFactor = (1.0f - SHADOW_MAP_BIAS) + distb * SHADOW_MAP_BIAS;
		shadowposition.xy /= distortFactor;
		shadowposition /= shadowposition.w;
		shadowposition = shadowposition * 0.5f + 0.5f;
		#ifdef SHADOW_FILTER
			for (int i = 0; i < 25; i++) {
				ivec2 px = ivec2((shadowposition.st + circle_offsets[i] * 0.0004f) * shadowMapResolution);
				float shadowDepth = texelFetch(shadowtex1, px, 0).x;
				float bias = cdepthN * 0.005;
				shade += float(shadowDepth + bias < shadowposition.z);
			}
			shade /= 25.0f;
		#else
			shade = shadowTexSmooth(shadowtex1, shadowposition.st, shadowposition.z);
		#endif
		float edgeX = abs(shadowposition.x) - 0.9f;
		float edgeY = abs(shadowposition.y) - 0.9f;
		shade -= max(0.0f, edgeX * 10.0f);
		shade -= max(0.0f, edgeY * 10.0f);

		float phong = 1.0 - (clamp(0.07f, angle, 1.0f) - 0.07f) * 1.07528f;
		if (is_plant) phong *= 0.2;
		shade = max(shade, phong);
	}
	//shade -= clamp((cdepthN - 0.7f) * 5.0f, 0.0f, 1.0f);
	shade = saturate(shade);
	return max(shade, extShadow);
}


#define PBR

#ifdef PBR
uniform sampler2D gaux1;

float GeometrySchlickGGX(float NdotV, float k) {
	float nom   = NdotV;
	float denom = NdotV * (1.0 - k) + k;

	return nom / denom;
}

float GeometrySmith(vec3 N, vec3 V, vec3 L, float k) {
	float NdotV = max(dot(N, V), 0.0);
	float NdotL = max(dot(N, L), 0.0);
	float ggx1 = GeometrySchlickGGX(NdotV, k);
	float ggx2 = GeometrySchlickGGX(NdotL, k);

	return ggx1 * ggx2;
}

float DistributionGGX(vec3 N, vec3 H, float roughness) {
  float a      = roughness*roughness;
  float a2     = a*a;
  float NdotH  = max(dot(N, H), 0.0);
  float NdotH2 = NdotH*NdotH;

  float nom   = a2;
  float denom = (NdotH2 * (a2 - 1.0) + 1.0);
  denom = PI * denom * denom;

  return nom / denom;
}

vec3 fresnelSchlickRoughness(float cosTheta, vec3 F0, float roughness) {
  return F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(1.0 - cosTheta, 5.0);
}

#endif

#define AO_Enabled
#ifdef AO_Enabled
float blurAO(float c, vec3 cNormal) {
	float a = c;
	lowp float d = 0.068 / cdepthN;

	for (int i = -5; i < 0; i++) {
		vec2 adj_coord = texcoord + vec2(0.0, 0.0027) * i * d;
		vec3 nvpos = texture(gdepth, adj_coord).rgb;
		a += mix(texture(composite, adj_coord).g, c, saturate(distance(nvpos, vpos.xyz))) * 0.2 * (6.0 - abs(float(i)));
	}

	for (int i = 1; i < 6; i++) {
		vec2 adj_coord = texcoord + vec2(0.0, 0.0027) * i * d;
		vec3 nvpos = texture(gdepth, adj_coord).rgb;
		a += mix(texture(composite, adj_coord).g, c, saturate(distance(nvpos, vpos.xyz))) * 0.2 * (6.0 - abs(float(i)));
	}

	return saturate(a * 0.1629 - 0.3) / 0.7;
}
#endif

#define GlobalIllumination
#ifdef GlobalIllumination
uniform sampler2D gaux4;
vec3 blurGI(vec3 c) {
	vec3 a = c;
	lowp float d = 0.068 / cdepthN;

	for (int i = -5; i < 0; i++) {
		vec2 adj_coord = texcoord + vec2(0.0, 0.0025) * i * d;
		vec3 nvpos = texture(gdepth, adj_coord).rgb;
		a += mix(texture(gaux4, adj_coord).rgb, c, saturate(distance(nvpos, vpos.xyz))) * 0.2 * (6.0 - abs(float(i)));
	}

	for (int i = 1; i < 6; i++) {
		vec2 adj_coord = texcoord + vec2(0.0, 0.0025) * i * d;
		vec3 nvpos = texture(gdepth, adj_coord).rgb;
		a += mix(texture(gaux4, adj_coord).rgb, c, saturate(distance(nvpos, vpos.xyz))) * 0.2 * (6.0 - abs(float(i)));
	}

	return a;
}
#endif

void main() {
	vec4 normaltex = texture(gnormal, texcoord);
	normal = normalize(normalDecode(normaltex.xy));
	wnormal = mat3(gbufferModelViewInverse) * normal;
	vec4 compositetex = texture(composite, texcoord);
	flag = compositetex.r;
	bool issky = (flag < 0.01);
	is_plant = (flag > 0.48 && flag < 0.53);
	vec2 mclight = vec2(0.0);
	float shade = 0.0, fogMul = 1.0;
	// Preprocess Gamma 2.2
	color = pow(color, vec3(2.2f));
	vec3 fogColor;

	float eyebrightness = pow(float(eyeBrightnessSmooth.x) / 120.0, 2.0);
	vec3 ambientColor = vec3(0.155, 0.16, 0.165) * (luma(suncolor) * 0.3 + (1.0 - eyebrightness) * 0.02);
	if (!issky) {
		shade = shadow_map();
		#ifdef CAUSTIC
		if (((flag > 0.71f && flag < 0.79f) && !isEyeInWater) || isEyeInWater) {
			float w = getwave(wpos.xyz + vec3(0.3, 0.0, 0.3) * (wpos.y + cameraPosition.y) + cameraPosition);
			shade += pow(clamp(0.0, w * 0.7, 1.0), 1.5) * 0.5;
			shade = clamp(shade, 0.0, 1.0);
		}
		#endif
		if(is_plant) shade /= 1.0 + mix(0.0, 2.0, max(0.0, pow(dot(normalize(vpos.xyz), lightPosition), 16.0)));
		mclight = texture(gaux2, texcoord).xy;

		const vec3 torchColor = vec3(2.55, 0.95, 0.3) * 0.45;

		float light_distance = clamp(0.08, (1.0 - pow(mclight.x, 2.6)), 1.0);
		const float light_quadratic = 4.9f;
		float max_light = 7.5 * mclight.x * mclight.x;
		const float light_constant1 = 1.09f;
		const float light_constant2 = 1.09f;
		float attenuation = clamp(0.0, light_constant1 / (pow(light_distance, light_quadratic)) - light_constant2, max_light);

		vec3 diffuse_torch = attenuation * torchColor;
		vec3 diffuse_sun = (1.0 - shade) * suncolor;

		#ifdef PBR
		vec4 specular = texture(gaux1, texcoord);
		bool is_plant = (flag > 0.49 && flag < 0.53);
		//if (flag < 0.6f || !is_plant) {
		//	diffuse_sun *= 0.63 + GeometrySmith(normal, normalize(wpos - vec3(0.0, -1.67, 0.0)), shadowLightPosition, specular.r) * 0.37;
		//}

		specular.r = clamp(0.01, specular.r, 0.99);
		vec3 V = normalize(vpos.xyz);
		vec3 F0 = vec3(0.02);
    F0 = mix(F0, color, specular.g);
    vec3 F = fresnelSchlickRoughness(max(dot(normal, V), 0.0), F0, specular.r);

		vec3 halfwayDir = normalize(lightPosition - V);
		vec3 no = GeometrySmith(normal, V, lightPosition, specular.r) * DistributionGGX(normal, halfwayDir, specular.r) * F;
		float denominator = 4 * max(dot(V, normal), 0.0) * max(dot(lightPosition, normal), 0.0) + 0.001;
		vec3 brdf = no / denominator;

		if(is_plant) shade /= 1.0 + mix(0.0, 2.0, max(0.0, pow(dot(halfwayDir, lightPosition), 16.0)));

		vec3 kS = F;
    vec3 kD = vec3(1.0) - kS;
    kD *= 1.0 - specular.g;

		diffuse_sun += (kD * color * PI + brdf) * max(0.0, dot(lightPosition, normal)) * (1.0 - shade);
		//diffuse_sun += no / denominator * diffuse_sun * max(dot(worldLightPos, normal), 0.0);
		// PBR specular, Red & Green reversed
		// Spec is in composite1.fsh
		diffuse_torch *= 1.0 - specular.r * 0.43;
		//diffuse_torch *= 1.0 + specular.b;
		#endif

		vec3 diffuse = diffuse_sun + diffuse_torch;

		// AO
		#ifdef AO_Enabled
		float ao = blurAO(compositetex.g, normal);
		color *= ao;
		#endif

		#ifdef GlobalIllumination
		diffuse += blurGI(texture(gaux4, texcoord).rgb) * 0.5;
		#endif
		float simulatedGI = 0.2 + 2.1 * mclight.y;
		color = color * diffuse + color * ambientColor * simulatedGI;
	} else {
		//vec3 hsl = rgbToHsl(color);
		//hsl = vibrance(hsl, 0.73);
		//color = hslToRgb(hsl);
	}

/* DRAWBUFFERS:35 */
	gl_FragData[0] = vec4(color, 1.0);
	gl_FragData[1] = vec4(mclight, shade, flag);
}
