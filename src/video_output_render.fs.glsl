/*
 * This file is part of bino, a 3D video player.
 *
 * Copyright (C) 2010-2011
 * Martin Lambers <marlam@marlam.de>
 * Frédéric Devernay <Frederic.Devernay@inrialpes.fr>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#version 120

// mode_onechannel
// mode_red_cyan_monochrome
// mode_red_cyan_half_color
// mode_red_cyan_full_color
// mode_red_cyan_dubois
// mode_green_magenta_monochrome
// mode_green_magenta_half_color
// mode_green_magenta_full_color
// mode_green_magenta_dubois
// mode_amber_blue_monochrome
// mode_amber_blue_half_color
// mode_amber_blue_full_color
// mode_amber_blue_dubois
// mode_red_green_monochrome
// mode_red_blue_monochrome
// mode_even_odd_rows
// mode_even_odd_columns
// mode_checkerboard
#define $mode

uniform sampler2D rgb_l;
uniform sampler2D rgb_r;
uniform float parallax;

#if defined(mode_onechannel)
uniform float channel;  // 0.0 for left, 1.0 for right
#endif

#if defined(mode_even_odd_rows) || defined(mode_even_odd_columns) || defined(mode_checkerboard)
uniform sampler2D mask_tex;
uniform float step_x;
uniform float step_y;
#endif

#if defined(mode_onechannel) || defined(mode_even_odd_rows) || defined(mode_even_odd_columns) || defined(mode_checkerboard)
uniform vec3 crosstalk;
#endif

#if defined(mode_red_cyan_monochrome) || defined(mode_red_cyan_half_color) || defined(mode_green_magenta_monochrome) || defined(mode_green_magenta_half_color) || defined(mode_amber_blue_monochrome) || defined(mode_amber_blue_half_color) || defined(mode_red_green_monochrome) || defined(mode_red_blue_monochrome)
float srgb_to_lum(vec3 srgb)
{
    // Values taken from http://www.fourcc.org/fccyvrgb.php
    return dot(srgb, vec3(0.299, 0.587, 0.114));
}
#endif

float linear_to_nonlinear(float x)
{
    return (x <= 0.0031308 ? (x * 12.92) : (1.055 * pow(x, 1.0 / 2.4) - 0.055));
}

vec3 rgb_to_srgb(vec3 rgb)
{
#if $srgb_broken
    return rgb;
#else
# if 1
    // Correct variant, see GL_ARB_framebuffer_sRGB extension
    float sr = linear_to_nonlinear(rgb.r);
    float sg = linear_to_nonlinear(rgb.g);
    float sb = linear_to_nonlinear(rgb.b);
    return vec3(sr, sg, sb);
# endif
# if 0
    // Faster variant
    return pow(rgb, 1.0 / 2.2);
# endif
# if 0
    // Even faster variant, assuming gamma = 2.0
    return sqrt(rgb);
# endif
#endif
}

#if defined(mode_onechannel) || defined(mode_even_odd_rows) || defined(mode_even_odd_columns) || defined(mode_checkerboard)
vec3 ghostbust(vec3 original, vec3 other)
{
    return original + crosstalk - (other + original) * crosstalk;
}
#endif

vec3 tex_l(vec2 texcoord)
{
    return texture2D(rgb_l, texcoord - vec2(parallax, 0.0)).rgb;
}

vec3 tex_r(vec2 texcoord)
{
    return texture2D(rgb_r, texcoord + vec2(parallax, 0.0)).rgb;
}

void main()
{
    vec3 srgb;

#if defined(mode_onechannel)

    vec3 rgbc_l = tex_l(gl_TexCoord[0].xy);
    vec3 rgbc_r = tex_r(gl_TexCoord[0].xy);
    srgb = rgb_to_srgb(ghostbust(mix(rgbc_l, rgbc_r, channel), mix(rgbc_r, rgbc_l, channel)));

#elif defined(mode_even_odd_rows) || defined(mode_even_odd_columns) || defined(mode_checkerboard)

    /* This implementation of the masked modes works around many different problems and therefore may seem strange.
     * Why not use stencil buffers?
     *  - Because we want to filter, to account for masked out features
     *  - Because stencil did not work with some drivers when switching fullscreen on/off
     * Why not use polygon stipple?
     *  - Because we want to filter, to account for masked out features
     *  - Because polygon stippling may not be hardware accelerated and is currently broken with many free drivers
     * Why use a mask texture? Why not use the mod() function to check for even/odd pixels?
     *  - Because mod() is broken with many drivers, and I found no reliable way to work around it. Some
     *    drivers seem to use extremely low precision arithmetic in the shaders; too low for reliable pixel
     *    position computations.
     */
    float m = texture2D(mask_tex, gl_TexCoord[1].xy).x;
# if defined(mode_even_odd_rows)
    vec3 rgb0_l = tex_l(gl_TexCoord[0].xy - vec2(0.0, step_y));
    vec3 rgb1_l = tex_l(gl_TexCoord[0].xy);
    vec3 rgb2_l = tex_l(gl_TexCoord[0].xy + vec2(0.0, step_y));
    vec3 rgbc_l = (rgb0_l + 2.0 * rgb1_l + rgb2_l) / 4.0;
    vec3 rgb0_r = tex_r(gl_TexCoord[0].xy - vec2(0.0, step_y));
    vec3 rgb1_r = tex_r(gl_TexCoord[0].xy);
    vec3 rgb2_r = tex_r(gl_TexCoord[0].xy + vec2(0.0, step_y));
    vec3 rgbc_r = (rgb0_r + 2.0 * rgb1_r + rgb2_r) / 4.0;
# elif defined(mode_even_odd_columns)
    vec3 rgb0_l = tex_l(gl_TexCoord[0].xy - vec2(step_x, 0.0));
    vec3 rgb1_l = tex_l(gl_TexCoord[0].xy);
    vec3 rgb2_l = tex_l(gl_TexCoord[0].xy + vec2(step_x, 0.0));
    vec3 rgbc_l = (rgb0_l + 2.0 * rgb1_l + rgb2_l) / 4.0;
    vec3 rgb0_r = tex_r(gl_TexCoord[0].xy - vec2(step_x, 0.0));
    vec3 rgb1_r = tex_r(gl_TexCoord[0].xy);
    vec3 rgb2_r = tex_r(gl_TexCoord[0].xy + vec2(step_x, 0.0));
    vec3 rgbc_r = (rgb0_r + 2.0 * rgb1_r + rgb2_r) / 4.0;
# elif defined(mode_checkerboard)
    vec3 rgb0_l = tex_l(gl_TexCoord[0].xy - vec2(0.0, step_y));
    vec3 rgb1_l = tex_l(gl_TexCoord[0].xy - vec2(step_x, 0.0));
    vec3 rgb2_l = tex_l(gl_TexCoord[0].xy);
    vec3 rgb3_l = tex_l(gl_TexCoord[0].xy + vec2(step_x, 0.0));
    vec3 rgb4_l = tex_l(gl_TexCoord[0].xy + vec2(0.0, step_y));
    vec3 rgbc_l = (rgb0_l + rgb1_l + 4.0 * rgb2_l + rgb3_l + rgb4_l) / 8.0;
    vec3 rgb0_r = tex_r(gl_TexCoord[0].xy - vec2(0.0, step_y));
    vec3 rgb1_r = tex_r(gl_TexCoord[0].xy - vec2(step_x, 0.0));
    vec3 rgb2_r = tex_r(gl_TexCoord[0].xy);
    vec3 rgb3_r = tex_r(gl_TexCoord[0].xy + vec2(step_x, 0.0));
    vec3 rgb4_r = tex_r(gl_TexCoord[0].xy + vec2(0.0, step_y));
    vec3 rgbc_r = (rgb0_r + rgb1_r + 4.0 * rgb2_r + rgb3_r + rgb4_r) / 8.0;
# endif
    srgb = rgb_to_srgb(ghostbust(mix(rgbc_r, rgbc_l, m), mix(rgbc_l, rgbc_r, m)));

#else // anaglyph modes
    // The Dubois anaglyph method is generally the highest quality.
    // Authors page: http://www.site.uottawa.ca/~edubois/anaglyph/
    // This method depends on the characteristics of the display device
    // and the anaglyph glasses. The matrices below are those published by the
    // author in these Flickr images:
    // http://www.flickr.com/photos/e_dubois/5132528166/
    // http://www.flickr.com/photos/e_dubois/5230654930/
    vec3 l = rgb_to_srgb(tex_l(gl_TexCoord[0].xy));
    vec3 r = rgb_to_srgb(tex_r(gl_TexCoord[0].xy));
# if defined(mode_red_cyan_monochrome)
    srgb = vec3(srgb_to_lum(l), srgb_to_lum(r), srgb_to_lum(r));
# elif defined(mode_red_cyan_half_color)
    srgb = vec3(srgb_to_lum(l), r.g, r.b);
# elif defined(mode_red_cyan_full_color)
    srgb = vec3(l.r, r.g, r.b);
# elif defined(mode_red_cyan_dubois)
    mat3 m0 = mat3(
             0.456, -0.040, -0.015,
             0.500, -0.038, -0.021,
             0.176, -0.016, -0.005);
    mat3 m1 = mat3(
            -0.043,  0.378, -0.072,
            -0.088,  0.734, -0.113,
            -0.002, -0.018,  1.226);
    srgb = m0 * l + m1 * r;
# elif defined(mode_green_magenta_monochrome)
    srgb = vec3(srgb_to_lum(r), srgb_to_lum(l), srgb_to_lum(r));
# elif defined(mode_green_magenta_half_color)
    srgb = vec3(r.r, srgb_to_lum(l), r.b);
# elif defined(mode_green_magenta_full_color)
    srgb = vec3(r.r, l.g, r.b);
# elif defined(mode_green_magenta_dubois)
    mat3 m0 = mat3(
            -0.062,  0.284, -0.015,
            -0.158,  0.668, -0.027,
            -0.039,  0.143,  0.021);
    mat3 m1 = mat3(
             0.529, -0.016,  0.009,
             0.705, -0.015,  0.075,
             0.024, -0.065,  0.937);
    srgb = vec3(r.r, l.g, r.b);
# elif defined(mode_amber_blue_monochrome)
    srgb = vec3(srgb_to_lum(l), srgb_to_lum(l), srgb_to_lum(r));
# elif defined(mode_amber_blue_half_color)
    srgb = vec3(srgb_to_lum(l), srgb_to_lum(l), r.b);
# elif defined(mode_amber_blue_full_color)
    srgb = vec3(l.r, l.g, r.b);
# elif defined(mode_amber_blue_dubois)
    mat3 m0 = mat3(
             1.062, -0.026, -0.038,
            -0.205,  0.908, -0.173,
             0.299,  0.068,  0.022);
    mat3 m1 = mat3(
            -0.016,  0.006,  0.094,
            -0.123,  0.062,  0.185,
            -0.017, -0.017,  0.911);
    srgb = m0 * l + m1 * r;
# elif defined(mode_red_green_monochrome)
    srgb = vec3(srgb_to_lum(l), srgb_to_lum(r), 0.0);
# elif defined(mode_red_blue_monochrome)
    srgb = vec3(srgb_to_lum(l), 0.0, srgb_to_lum(r));
# endif

#endif

    gl_FragColor = vec4(srgb, 1.0);
}
