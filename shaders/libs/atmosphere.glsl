// ============
const float R0 = 6360e3;
const float Ra = 6380e3;
#ifdef AT_LSTEP
const int steps = 4;
const int stepss = 2;
#else
const int steps = 8;
const int stepss = 4;
#endif
const float g = .76;
const float g2 = g * g;
const float Hr = 8e3;
const float Hm = 1.6e3;
const vec3 I = vec3(1.2311, 1.0, 0.8286) * 20.0;

#define t iTime

const vec3 C = vec3(0., -R0, 0.);
const vec3 bM = vec3(21e-6);
const vec3 bR = vec3(5.8e-6, 13.5e-6, 33.1e-6);

void densities(in vec3 pos, out float rayleigh, out float mie) {
	float h = length(pos - C) - R0;
	rayleigh =  exp(-h/Hr);
	mie = exp(-h/Hm);
}

float escape(in vec3 p, in vec3 d, in float R) {
	vec3 v = p - C;
	float b = dot(v, d);
	float c = dot(v, v) - R*R;
	float det2 = b * b - c;
	if (det2 < 0.) return -1.;
	float det = sqrt(det2);
	float t1 = -b - det, t2 = -b + det;
	return (t1 >= 0.) ? t1 : t2;
}

// this can be explained: http://www.scratchapixel.com/lessons/3d-advanced-lessons/simulating-the-colors-of-the-sky/atmospheric-scattering/
vec3 scatter(vec3 o, vec3 d, vec3 Ds, float l) {
	if (d.y < 0.0) d.y = 0.0004 / (-d.y + 0.02) - 0.02;

	float L = min(l, escape(o, d, Ra));
	float mu = dot(d, Ds);
	float opmu2 = 1. + mu*mu;
	float phaseR = .0596831 * opmu2;
	float phaseM = .1193662 * (1. - g2) * opmu2 / ((2. + g2) * pow(1. + g2 - 2.*g*mu, 1.5));

	float depthR = 0., depthM = 0.;
	vec3 R = vec3(0.), M = vec3(0.);

	//float dl = L / float(steps);
	float u0 = - (L - 100.0) / (1.0 - exp2(steps));

	for (int i = 0; i < steps; ++i) {
		float dl = u0 * exp2(i);
		float l = - u0 * (1 - exp2(i + 1));//float(i) * dl;
		vec3 p = o + d * l;

		float dR, dM;
		densities(p, dR, dM);
		dR *= dl; dM *= dl;
		depthR += dR;
		depthM += dM;

		float Ls = escape(p, Ds, Ra);
		if (Ls > 0.) {
			float dls = Ls / float(stepss);
			float depthRs = 0., depthMs = 0.;
			for (int j = 0; j < stepss; ++j) {
				float ls = float(j) * dls;
				vec3 ps = p + Ds * ls;
				float dRs, dMs;
				densities(ps, dRs, dMs);
				depthRs += dRs;
				depthMs += dMs;
			}
      depthRs *= dls;
      depthMs *= dls;

			vec3 A = exp(-(bR * (depthRs + depthR) + bM * (depthMs + depthM)));
			R += A * dR;
			M += A * dM;
		} else {
			return vec3(0.);
		}
	}

	return I * (R * bR * phaseR + M * bM * phaseM);
}
// ============

#ifdef CrespecularRays

#ifdef HIGH_QUALITY_Crespecular
const float vl_steps = 48.0;
const int vl_loop = 48;
#else
const float vl_steps = 8.0;
const int vl_loop = 8;
#endif

float VL(vec2 uv, vec3 owpos, out float vl) {
	vec3 adj_owpos = owpos - vec3(0.0,1.62,0.0);
	float adj_depth = length(adj_owpos);

	vec3 swpos = owpos;
	float step_length = min(shadowDistance, adj_depth) / vl_steps;
	vec3 dir = normalize(adj_owpos) * step_length;
	float prev = 0.0, total = 0.0;

	float dither = bayer_16x16(uv, vec2(viewWidth, viewHeight));

	for (int i = 0; i < vl_loop; i++) {
		swpos -= dir;
		dither = fract(dither + 0.618);
		vec3 shadowpos = wpos2shadowpos(swpos + dir * dither);
		float sdepth = texture2D(shadowtex0, shadowpos.xy).x;

		float hit = float(shadowpos.z + 0.0006 < sdepth);
		total += (prev + hit) * step_length * 0.5;

		prev = hit;
	}

	total = min(total, 512.0);
	vl = total / 512.0f;

	return (max(0.0, adj_depth - shadowDistance) + total) / 512.0f;
}
#endif
