#!/usr/bin/env python3
"""Make a PNG contact sheet (and optionally per-frame PNGs) from 96x64 PPM frame dumps.

  python frames.py DIR [--out sheet.png] [--cols 6] [--scale 3] [--max 36] [--pngs]
No third-party modules needed (zlib PNG writer).
"""
import argparse, glob, os, struct, zlib


def read_ppm(fn):
    d = open(fn, 'rb').read()
    parts = d.split(b'\n', 3)
    w, h = map(int, parts[1].split())
    return w, h, parts[3]


def write_png(fn, w, h, rgb):
    raw = b''.join(b'\0' + rgb[y*w*3:(y+1)*w*3] for y in range(h))
    def chunk(t, b):
        return struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t + b) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) \
        + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
    open(fn, 'wb').write(png)


def scale(w, h, rgb, s):
    out = bytearray()
    for y in range(h):
        row = bytearray()
        for x in range(w):
            row += rgb[(y*w+x)*3:(y*w+x)*3+3] * s
        out += bytes(row) * s
    return w*s, h*s, bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dir')
    ap.add_argument('--out', default=None)
    ap.add_argument('--cols', type=int, default=6)
    ap.add_argument('--scale', type=int, default=3)
    ap.add_argument('--max', type=int, default=36)
    ap.add_argument('--pngs', action='store_true')
    a = ap.parse_args()
    files = sorted(glob.glob(os.path.join(a.dir, '*.ppm')))
    if len(files) > a.max:
        step = len(files) / a.max
        files = [files[int(i * step)] for i in range(a.max)]
    frames = []
    for f in files:
        w, h, rgb = read_ppm(f)
        w, h, rgb = scale(w, h, rgb, a.scale)
        frames.append((w, h, rgb))
        if a.pngs:
            write_png(f[:-4] + '.png', w, h, rgb)
    if not frames:
        raise SystemExit('no frames')
    w, h = frames[0][0], frames[0][1]
    gap = 4
    cols = min(a.cols, len(frames))
    rows = (len(frames) + cols - 1) // cols
    W, H = cols * (w + gap) + gap, rows * (h + gap) + gap
    sheet = bytearray(b'\x20' * (W * H * 3))
    for i, (_, _, rgb) in enumerate(frames):
        ox, oy = gap + (i % cols) * (w + gap), gap + (i // cols) * (h + gap)
        for y in range(h):
            o = ((oy + y) * W + ox) * 3
            sheet[o:o + w*3] = rgb[y*w*3:(y+1)*w*3]
    out = a.out or os.path.join(a.dir, 'sheet.png')
    write_png(out, W, H, bytes(sheet))
    print(out, f'{len(frames)} frames')


if __name__ == '__main__':
    main()
