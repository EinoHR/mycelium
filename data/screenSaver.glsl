#version 330
// -- part of the filter interface, every filter has these
in vec2 v_texCoord0;
uniform sampler2D tex0;
out vec4 o_color;

// -- user parameters
uniform float gain;
uniform float time;
uniform float scale;

uniform sampler2D distortMap;

uniform vec2 size;
uniform float rowSizePx;

uniform int edgePxls;

uniform bool blurEdges;

vec2 px = vec2(1.0, 1.0)/size;
int rowIndex = int((v_texCoord0.y * size.y) / rowSizePx);

float PI = 3.1415926;
float EaseInSine(float x) {
 return 1.0 - cos((x * PI) / 2.0);
}
float EaseOutSine(float x){
 return sin((x * PI) / 2.0);
}


/* discontinuous pseudorandom uniformly distributed in [-0.5, +0.5]^3 */
vec3 random3(vec3 c) {
     float j = 4096.0*sin(dot(c,vec3(17.0, 59.4, 15.0)));
     vec3 r;
     r.z = fract(512.0*j);
     j *= .125;
     r.x = fract(512.0*j);
     j *= .125;
     r.y = fract(512.0*j);
     return r-0.5;
}

/* skew constants for 3d simplex functions */
const float F3 =  0.3333333;
const float G3 =  0.1666667;

/* 3d simplex noise */
float simplex3d(vec3 p) {
     /* 1. find current tetrahedron T and it's four vertices */
     /* s, s+i1, s+i2, s+1.0 - absolute skewed (integer) coordinates of T vertices */
     /* x, x1, x2, x3 - unskewed coordinates of p relative to each of T vertices*/

     /* calculate s and x */
     vec3 s = floor(p + dot(p, vec3(F3)));
     vec3 x = p - s + dot(s, vec3(G3));

     /* calculate i1 and i2 */
     vec3 e = step(vec3(0.0), x - x.yzx);
     vec3 i1 = e*(1.0 - e.zxy);
     vec3 i2 = 1.0 - e.zxy*(1.0 - e);

     /* x1, x2, x3 */
     vec3 x1 = x - i1 + G3;
     vec3 x2 = x - i2 + 2.0*G3;
     vec3 x3 = x - 1.0 + 3.0*G3;

     /* 2. find four surflets and store them in d */
     vec4 w, d;

     /* calculate surflet weights */
     w.x = dot(x, x);
     w.y = dot(x1, x1);
     w.z = dot(x2, x2);
     w.w = dot(x3, x3);

     /* w fades from 0.6 at the center of the surflet to 0.0 at the margin */
     w = max(0.6 - w, 0.0);

     /* calculate surflet components */
     d.x = dot(random3(s), x);
     d.y = dot(random3(s + i1), x1);
     d.z = dot(random3(s + i2), x2);
     d.w = dot(random3(s + 1.0), x3);

     /* multiply d by w^4 */
     w *= w;
     w *= w;
     d *= w;

     /* 3. return the sum of the four surflets */
     return dot(d, vec4(52.0));
}

/* const matrices for 3d rotation */
const mat3 rot1 = mat3(-0.37, 0.36, 0.85,-0.14,-0.93, 0.34,0.92, 0.01,0.4);
const mat3 rot2 = mat3(-0.55,-0.39, 0.74, 0.33,-0.91,-0.24,0.77, 0.12,0.63);
const mat3 rot3 = mat3(-0.71, 0.52,-0.47,-0.08,-0.72,-0.68,-0.7,-0.45,0.56);

/* directional artifacts can be reduced by rotating each octave */
float simplex3d_fractal(vec3 m) {
     return   0.5333333*simplex3d(m*rot1)
     +0.2666667*simplex3d(2.0*m*rot2)
     +0.1333333*simplex3d(4.0*m*rot3)
     +0.0666667*simplex3d(8.0*m);
}

float map(float value, float min1, float max1, float min2, float max2) {
    return min2 + (value - min1) * (max2 - min2) / (max1 - min1);
}

vec2 wrapUv(vec2 uv) {
     if (uv.x > 1.0) {
         uv.y += rowSizePx*px.y;
     } else if (uv.x < 0.0) {
         uv.y -= rowSizePx*px.y;
     }
     uv.x = fract(uv.x);
     return uv;
}


vec4 blur9(sampler2D image, vec2 uv, vec2 resolution, vec2 direction) {
     vec4 color = vec4(0.0);
     vec2 off1 = vec2(1.3846153846) * direction;
     vec2 off2 = vec2(3.2307692308) * direction;
     color += texture2D(image, uv) * 0.2270270270;
     color += texture2D(image, wrapUv(uv + (off1 / resolution))) * 0.3162162162;
     color += texture2D(image, wrapUv(uv - (off1 / resolution))) * 0.3162162162;
     color += texture2D(image, wrapUv(uv + (off2 / resolution))) * 0.0702702703;
     color += texture2D(image, wrapUv(uv - (off2 / resolution))) * 0.0702702703;
     return color;
}

void main() {
    vec4 amount = texture(distortMap, v_texCoord0);

    float x = v_texCoord0.x + rowIndex;
    float y = (int(v_texCoord0.y * size.y) % int(rowSizePx)) / size.y;

    float xNoiseRaw = simplex3d_fractal(vec3(x, y, time)*scale);
    float xNoise = gain * 2.0 * (xNoiseRaw-0.5);
    float yNoiseRaw = simplex3d_fractal(vec3(x, y, time+999)*scale);
    float yNoise = gain * 2.0 * (yNoiseRaw-0.5);

    vec2 newCoord = v_texCoord0 + vec2(xNoise, yNoise)*amount.r;

    vec4 col = texture(tex0, newCoord);

    if (newCoord.x < 0.0) {
        newCoord = vec2(
            1.0-newCoord.x,
            newCoord.y - rowSizePx*px.y
        );
    }
    else if (newCoord.x > 1.0) {
        newCoord = vec2(
            newCoord.x-1.0,
            newCoord.y + rowSizePx*px.y
        );
    }

    vec4 mixCol;
    if (blurEdges) {
        mixCol = blur9(tex0, v_texCoord0, size, vec2(0.5, 0.1));
    }
    else {
        mixCol = texture(tex0, v_texCoord0);
    }
    float edgePxlSize = edgePxls*px.x;
    if (v_texCoord0.x < edgePxlSize) {
        float fac = EaseOutSine(map(v_texCoord0.x, 0.0, edgePxlSize, 0.0, 1.0));
        col = mix(mixCol, col, fac);
    }
    else if (v_texCoord0.x > 1.0-edgePxlSize) {
        float fac = EaseOutSine(map(v_texCoord0.x, 1.0, 1.0-edgePxlSize, 0.0, 1.0));
        col = mix(mixCol, col, fac);
    }

    o_color = col;
//    o_color = vec4(xNoiseRaw+0.5, yNoiseRaw+0.5, 0.0, 1.0);
}