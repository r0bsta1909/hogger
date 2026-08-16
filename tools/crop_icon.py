# tools/crop_icon.py - Einmalwerkzeug, NICHT Teil von Build oder Tests.
# Schneidet ein Icon-PNG (RGBA8) auf den quadratischen Bereich seines
# sichtbaren Inhalts zu (Alpha-Bounding-Box, zentriert) und speichert es
# an derselben Stelle. Fuer Finaldateien, die als Icon mit Rand auf einer
# breiten Leinwand exportiert wurden (GDD 17.5 verlangt quadratisch).
# Aufruf: python tools/crop_icon.py assets/icon_priest.png [...]
# Reines Python, keine Bibliotheken - LOEVE haette dafuer laufen muessen.

import struct, zlib, sys

def read_png(path):
    d = open(path,'rb').read()
    assert d[:8] == b'\x89PNG\r\n\x1a\n'
    pos = 8; idat = b''; w=h=None
    while pos < len(d):
        ln = struct.unpack(">I", d[pos:pos+4])[0]; typ = d[pos+4:pos+8]
        data = d[pos+8:pos+8+ln]; pos += 12+ln
        if typ == b'IHDR':
            w,h,bd,ct,cp,fl,il = struct.unpack(">IIBBBBB", data)
            assert bd==8 and ct==6 and il==0
        elif typ == b'IDAT': idat += data
        elif typ == b'IEND': break
    raw = zlib.decompress(idat); stride = w*4
    out = bytearray(w*h*4); prev = bytearray(stride); p = 0
    for y in range(h):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p+stride]); p += stride
        if f == 1:
            for i in range(4, stride): line[i] = (line[i] + line[i-4]) & 255
        elif f == 2:
            for i in range(stride): line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                a = line[i-4] if i >= 4 else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i-4] if i >= 4 else 0
                b = prev[i]; c = prev[i-4] if i >= 4 else 0
                pp = a+b-c; pa=abs(pp-a); pb=abs(pp-b); pc=abs(pp-c)
                pr = a if (pa<=pb and pa<=pc) else (b if pb<=pc else c)
                line[i] = (line[i] + pr) & 255
        out[y*stride:(y+1)*stride] = line
        prev = line
    return w,h,out

def write_png(path, w, h, px):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += px[y*w*4:(y+1)*w*4]
    def chunk(t, data):
        return struct.pack(">I", len(data)) + t + data + struct.pack(">I", zlib.crc32(t+data) & 0xffffffff)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    out = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b'')
    open(path,'wb').write(out)

def bbox(w,h,px,t=10):
    x0,y0,x1,y1 = w,h,-1,-1
    for y in range(h):
        row = y*w*4
        for x in range(w):
            if px[row+x*4+3] > t:
                if x<x0: x0=x
                if x>x1: x1=x
                if y<y0: y0=y
                if y>y1: y1=y
    return x0,y0,x1,y1

def crop_square(path):
    w,h,px = read_png(path)
    x0,y0,x1,y1 = bbox(w,h,px)
    bw, bh = x1-x0+1, y1-y0+1
    side = max(bw,bh)
    cx, cy = (x0+x1)//2, (y0+y1)//2
    sx, sy = cx - side//2, cy - side//2
    out = bytearray(side*side*4)
    for y in range(side):
        syy = sy + y
        if syy < 0 or syy >= h: continue
        for x in range(side):
            sxx = sx + x
            if sxx < 0 or sxx >= w: continue
            si = (syy*w + sxx)*4; di = (y*side + x)*4
            out[di:di+4] = px[si:si+4]
    write_png(path, side, side, out)
    return (w,h),(side,side)

for p in sys.argv[1:]:
    print(p, *crop_square(p))
