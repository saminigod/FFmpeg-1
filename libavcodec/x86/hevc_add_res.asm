; *****************************************************************************
; * Provide SIMD optimizations for add_residual functions for HEVC decoding
; * Copyright (c) 2014 Pierre-Edouard LEPERE
; *
; * This file is part of FFmpeg.
; *
; * FFmpeg is free software; you can redistribute it and/or
; * modify it under the terms of the GNU Lesser General Public
; * License as published by the Free Software Foundation; either
; * version 2.1 of the License, or (at your option) any later version.
; *
; * FFmpeg is distributed in the hope that it will be useful,
; * but WITHOUT ANY WARRANTY; without even the implied warranty of
; * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
; * Lesser General Public License for more details.
; *
; * You should have received a copy of the GNU Lesser General Public
; * License along with FFmpeg; if not, write to the Free Software
; * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
; ******************************************************************************

%include "libavutil/x86/x86util.asm"

SECTION .text

cextern pw_1023
%define max_pixels_10 pw_1023

; the add_res macros and functions were largely inspired by h264_idct.asm from the x264 project
%macro ADD_RES_MMX_4_8 0
    mova              m2, [r1]
    mova              m4, [r1+8]
    pxor              m3, m3
    psubw             m3, m2
    packuswb          m2, m2
    packuswb          m3, m3
    pxor              m5, m5
    psubw             m5, m4
    packuswb          m4, m4
    packuswb          m5, m5

    movh              m0, [r0]
    movh              m1, [r0+r2]
    paddusb           m0, m2
    paddusb           m1, m4
    psubusb           m0, m3
    psubusb           m1, m5
    movh            [r0], m0
    movh         [r0+r2], m1
%endmacro


INIT_MMX mmxext
; void ff_hevc_add_residual_4_8_mmxext(uint8_t *dst, int16_t *res, ptrdiff_t stride)
cglobal hevc_add_residual_4_8, 3, 3, 6
    ADD_RES_MMX_4_8
    add               r1, 16
    lea               r0, [r0+r2*2]
    ADD_RES_MMX_4_8
    RET

%macro ADD_RES_SSE_8_8 0
    pxor              m3, m3
    mova              m4, [r1]
    mova              m6, [r1+16]
    mova              m0, [r1+32]
    mova              m2, [r1+48]
    psubw             m5, m3, m4
    psubw             m7, m3, m6
    psubw             m1, m3, m0
    packuswb          m4, m0
    packuswb          m5, m1
    psubw             m3, m2
    packuswb          m6, m2
    packuswb          m7, m3

    movq              m0, [r0]
    movq              m1, [r0+r2]
    movhps            m0, [r0+r2*2]
    movhps            m1, [r0+r3]
    paddusb           m0, m4
    paddusb           m1, m6
    psubusb           m0, m5
    psubusb           m1, m7
    movq            [r0], m0
    movq         [r0+r2], m1
    movhps     [r0+2*r2], m0
    movhps       [r0+r3], m1
%endmacro

%macro ADD_RES_SSE_16_32_8 3
    mova             xm2, [r1+%1]
    mova             xm6, [r1+%1+16]
%if cpuflag(avx2)
    vinserti128       m2, m2, [r1+%1+32], 1
    vinserti128       m6, m6, [r1+%1+48], 1
%endif
%if cpuflag(avx)
    psubw             m1, m0, m2
    psubw             m5, m0, m6
%else
    mova              m1, m0
    mova              m5, m0
    psubw             m1, m2
    psubw             m5, m6
%endif
    packuswb          m2, m6
    packuswb          m1, m5

    mova             xm4, [r1+%1+mmsize*2]
    mova             xm6, [r1+%1+mmsize*2+16]
%if cpuflag(avx2)
    vinserti128       m4, m4, [r1+%1+96 ], 1
    vinserti128       m6, m6, [r1+%1+112], 1
%endif
%if cpuflag(avx)
    psubw             m3, m0, m4
    psubw             m5, m0, m6
%else
    mova              m3, m0
    mova              m5, m0
    psubw             m3, m4
    psubw             m5, m6
%endif
    packuswb          m4, m6
    packuswb          m3, m5

    paddusb           m2, [%2]
    paddusb           m4, [%3]
    psubusb           m2, m1
    psubusb           m4, m3
    mova            [%2], m2
    mova            [%3], m4
%endmacro


%macro TRANSFORM_ADD_8 0
; void ff_hevc_add_residual_8_8_<opt>(uint8_t *dst, int16_t *res, ptrdiff_t stride)
cglobal hevc_add_residual_8_8, 3, 4, 8
    lea               r3, [r2*3]
    ADD_RES_SSE_8_8
    add               r1, 64
    lea               r0, [r0+r2*4]
    ADD_RES_SSE_8_8
    RET

; void ff_hevc_add_residual_16_8_<opt>(uint8_t *dst, int16_t *res, ptrdiff_t stride)
cglobal hevc_add_residual_16_8, 3, 5, 7
    pxor                m0, m0
    lea                 r3, [r2*3]
    mov                r4d, 4
.loop:
    ADD_RES_SSE_16_32_8  0, r0,      r0+r2
    ADD_RES_SSE_16_32_8 64, r0+r2*2, r0+r3
    add                 r1, 128
    lea                 r0, [r0+r2*4]
    dec                r4d
    jg .loop
    RET

; void ff_hevc_add_residual_32_8_<opt>(uint8_t *dst, int16_t *res, ptrdiff_t stride)
cglobal hevc_add_residual_32_8, 3, 5, 7
    pxor                m0, m0
    mov                r4d, 16
.loop:
    ADD_RES_SSE_16_32_8  0, r0,    r0+16
    ADD_RES_SSE_16_32_8 64, r0+r2, r0+r2+16
    add                 r1, 128
    lea                 r0, [r0+r2*2]
    dec                r4d
    jg .loop
    RET
%endmacro

INIT_XMM sse2
TRANSFORM_ADD_8
INIT_XMM avx
TRANSFORM_ADD_8

%if HAVE_AVX2_EXTERNAL
INIT_YMM avx2
; void ff_hevc_add_residual_32_8_avx2(uint8_t *dst, int16_t *res, ptrdiff_t stride)
cglobal hevc_add_residual_32_8, 3, 5, 7
    pxor                 m0, m0
    lea                  r3, [r2*3]
    mov                 r4d, 8
.loop:
    ADD_RES_SSE_16_32_8   0, r0,      r0+r2
    ADD_RES_SSE_16_32_8 128, r0+r2*2, r0+r3
    add                  r1, 256
    lea                  r0, [r0+r2*4]
    dec                 r4d
    jg .loop
    RET
%endif

%macro ADD_RES_SSE_8_10 4
    mova              m0, [%4]
    mova              m1, [%4+16]
    mova              m2, [%4+32]
    mova              m3, [%4+48]
    paddw             m0, [%1+0]
    paddw             m1, [%1+%2]
    paddw             m2, [%1+%2*2]
    paddw             m3, [%1+%3]
    CLIPW             m0, m4, m5
    CLIPW             m1, m4, m5
    CLIPW             m2, m4, m5
    CLIPW             m3, m4, m5
    mova          [%1+0], m0
    mova         [%1+%2], m1
    mova       [%1+%2*2], m2
    mova         [%1+%3], m3
%endmacro

%macro ADD_RES_MMX_4_10 3
    mova              m0, [%1+0]
    mova              m1, [%1+%2]
    paddw             m0, [%3]
    paddw             m1, [%3+8]
    CLIPW             m0, m2, m3
    CLIPW             m1, m2, m3
    mova          [%1+0], m0
    mova         [%1+%2], m1
%endmacro

%macro ADD_RES_SSE_16_10 3
    mova              m0, [%3]
    mova              m1, [%3+16]
    mova              m2, [%3+32]
    mova              m3, [%3+48]
    paddw             m0, [%1]
    paddw             m1, [%1+16]
    paddw             m2, [%1+%2]
    paddw             m3, [%1+%2+16]
    CLIPW             m0, m4, m5
    CLIPW             m1, m4, m5
    CLIPW             m2, m4, m5
    CLIPW             m3, m4, m5
    mova            [%1], m0
    mova         [%1+16], m1
    mova         [%1+%2], m2
    mova      [%1+%2+16], m3
%endmacro

%macro ADD_RES_SSE_32_10 2
    mova              m0, [%2]
    mova              m1, [%2+16]
    mova              m2, [%2+32]
    mova              m3, [%2+48]

    paddw             m0, [%1]
    paddw             m1, [%1+16]
    paddw             m2, [%1+32]
    paddw             m3, [%1+48]
    CLIPW             m0, m4, m5
    CLIPW             m1, m4, m5
    CLIPW             m2, m4, m5
    CLIPW             m3, m4, m5
    mova            [%1], m0
    mova         [%1+16], m1
    mova         [%1+32], m2
    mova         [%1+48], m3
%endmacro

%macro ADD_RES_AVX2_16_10 4
    mova              m0, [%4]
    mova              m1, [%4+32]
    mova              m2, [%4+64]
    mova              m3, [%4+96]

    paddw             m0, [%1+0]
    paddw             m1, [%1+%2]
    paddw             m2, [%1+%2*2]
    paddw             m3, [%1+%3]

    CLIPW             m0, m4, m5
    CLIPW             m1, m4, m5
    CLIPW             m2, m4, m5
    CLIPW             m3, m4, m5
    mova          [%1+0], m0
    mova         [%1+%2], m1
    mova       [%1+%2*2], m2
    mova         [%1+%3], m3
%endmacro

%macro ADD_RES_AVX2_32_10 3
    mova              m0, [%3]
    mova              m1, [%3+32]
    mova              m2, [%3+64]
    mova              m3, [%3+96]

    paddw             m0, [%1]
    paddw             m1, [%1+32]
    paddw             m2, [%1+%2]
    paddw             m3, [%1+%2+32]

    CLIPW             m0, m4, m5
    CLIPW             m1, m4, m5
    CLIPW             m2, m4, m5
    CLIPW             m3, m4, m5
    mova            [%1], m0
    mova         [%1+32], m1
    mova         [%1+%2], m2
    mova      [%1+%2+32], m3
%endmacro

; void ff_hevc_add_residual_<4|8|16|32>_10(pixel *dst, int16_t *block, ptrdiff_t stride)
INIT_MMX mmxext
cglobal hevc_add_residual_4_10, 3, 3, 6
    pxor              m2, m2
    mova              m3, [max_pixels_10]
    ADD_RES_MMX_4_10  r0, r2, r1
    add               r1, 16
    lea               r0, [r0+2*r2]
    ADD_RES_MMX_4_10  r0, r2, r1
    RET

INIT_XMM sse2
cglobal hevc_add_residual_8_10, 3, 4, 6
    pxor              m4, m4
    mova              m5, [max_pixels_10]
    lea               r3, [r2*3]

    ADD_RES_SSE_8_10  r0, r2, r3, r1
    lea               r0, [r0+r2*4]
    add               r1, 64
    ADD_RES_SSE_8_10  r0, r2, r3, r1
    RET

cglobal hevc_add_residual_16_10, 3, 5, 6
    pxor              m4, m4
    mova              m5, [max_pixels_10]

    mov              r4d, 8
.loop:
    ADD_RES_SSE_16_10 r0, r2, r1
    lea               r0, [r0+r2*2]
    add               r1, 64
    dec              r4d
    jg .loop
    RET

cglobal hevc_add_residual_32_10, 3, 5, 6
    pxor              m4, m4
    mova              m5, [max_pixels_10]

    mov              r4d, 32
.loop:
    ADD_RES_SSE_32_10 r0, r1
    lea               r0, [r0+r2]
    add               r1, 64
    dec              r4d
    jg .loop
    RET

%if HAVE_AVX2_EXTERNAL
INIT_YMM avx2
cglobal hevc_add_residual_16_10, 3, 5, 6
    pxor               m4, m4
    mova               m5, [max_pixels_10]
    lea                r3, [r2*3]

    mov               r4d, 4
.loop:
    ADD_RES_AVX2_16_10 r0, r2, r3, r1
    lea                r0, [r0+r2*4]
    add                r1, 128
    dec               r4d
    jg .loop
    RET

cglobal hevc_add_residual_32_10, 3, 5, 6
    pxor               m4, m4
    mova               m5, [max_pixels_10]

    mov               r4d, 16
.loop:
    ADD_RES_AVX2_32_10 r0, r2, r1
    lea                r0, [r0+r2*2]
    add                r1, 128
    dec               r4d
    jg .loop
    RET
%endif ;HAVE_AVX2_EXTERNAL
