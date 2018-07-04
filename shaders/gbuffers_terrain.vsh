/*
 * Copyright 2017 Cheng Cao
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// =============================================================================
//  PLEASE FOLLOW THE LICENSE AND PLEASE DO NOT REMOVE THE LICENSE HEADER
// =============================================================================
//  ANY USE OF THE SHADER ONLINE OR OFFLINE IS CONSIDERED AS INCLUDING THE CODE
//  IF YOU DOWNLOAD THE SHADER, IT MEANS YOU AGREE AND OBSERVE THIS LICENSE
// =============================================================================

#version 120

#include "libs/compat.glsl"

#pragma optimize(on)

#define NORMALS

attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;
attribute vec4 at_tangent;

uniform mat4 gbufferModelViewInverse;
uniform float rainStrength;
uniform float frameTimeCounter;

varying f16vec4 color;
varying vec4 coords;
varying vec4 wdata;

varying float dis;

#define normal wdata.xyz
#define flag wdata.w

#define texcoord coords.rg
#define lmcoord coords.ba

#ifdef NORMALS
varying f16vec3 tangent;
varying f16vec3 binormal;
#else
f16vec3 tangent;
f16vec3 binormal;
#endif

varying vec2 nflat;

#define ParallaxOcclusion
#ifdef ParallaxOcclusion
varying f16vec3 tangentpos;
#endif

//#define PARALLAX_SELF_SHADOW
#ifdef PARALLAX_SELF_SHADOW
varying vec3 sun;

uniform vec3 shadowLightPosition;
#endif

#define WAVING_FOILAGE

#define hash(p) fract(mod(p.x, 1.0) * 73758.23f - p.y)

#include "libs/encoding.glsl"

//#define TAA
#ifdef TAA
#include "libs/TAAjitter.glsl"
#endif

void main() {
	color = gl_Color;

	normal = normalize(gl_NormalMatrix * gl_Normal);

	tangent = normalize(gl_NormalMatrix * at_tangent.xyz);
  binormal = cross(tangent, normal);

	vec4 position = gl_Vertex;
	float blockId = mc_Entity.x;
	flag = terrianFlag;

	#ifdef WAVING_FOILAGE
	float maxStrength = 1.0 + rainStrength * 0.5;
	float time = frameTimeCounter * 3.0;
	#endif

	if (blockId == 31.0 || blockId == 37.0 || blockId == 38.0 || blockId == 59.0 || blockId == 141.0 || blockId == 142.0) {
		#ifdef WAVING_FOILAGE
		if (gl_MultiTexCoord0.t < mc_midTexCoord.t) {
			float rand_ang = hash(position.xz);
			float reset = cos(rand_ang * 10.0 + time * 0.1);
			reset = max( reset * reset, max(rainStrength, 0.1));
			position.x += (sin(rand_ang * 10.0 + time + position.y) * 0.2) * (reset * maxStrength);
		}
		#endif
		color.a *= 0.4;
		flag = foilage2Flag;
	} else if(mc_Entity.x == 18.0 || mc_Entity.x == 106.0 || mc_Entity.x == 161.0 || mc_Entity.x == 175.0) {
		#ifdef WAVING_FOILAGE
		float rand_ang = hash(position.xz);
		float reset = cos(rand_ang * 10.0 + time * 0.1);
		reset = max( reset * reset, max(rainStrength, 0.1));
		position.xyz += (sin(rand_ang * 5.0 + time + position.y) * 0.035 + 0.035) * (reset * maxStrength) * tangent;
		#endif
		flag = foilage1Flag;
	} else if (blockId == 83.0 || blockId == 39 || blockId == 40 || blockId == 6.0 || blockId == 104 || blockId == 105 || blockId == 115) flag = foilage2Flag;

	position = gl_ModelViewMatrix * position;
	vec3 wpos = position.xyz;
	position = gl_ProjectionMatrix * position;
	#ifdef TAA
	position.xyz /= position.w;
	TemporalJitterProjPos(position);
	position.xyz *= position.w;
	#endif
	gl_Position = position;

	texcoord = gl_MultiTexCoord0.st;
	lmcoord = (gl_TextureMatrix[1] *  gl_MultiTexCoord1).xy;

	#ifdef ParallaxOcclusion
	f16mat3 TBN = f16mat3(tangent, binormal, normal);
	tangentpos = normalize(wpos * TBN);
	#ifdef PARALLAX_SELF_SHADOW
	sun = TBN * normalize(shadowLightPosition);
	#endif
	#endif

	nflat = normalEncode(normal);

	dis = length(wpos);
}
