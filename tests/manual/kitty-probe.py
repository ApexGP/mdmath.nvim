#!/usr/bin/env python3
"""Probe what this terminal supports for mdmath.nvim.

Four labeled blocks are printed, each isolating one layer:

  1) plain direct PNG, no placeholders (a=T, t=d)
     -> does the terminal render kitty graphics at all?
  2) placeholders + file transmission (a=T, U=1, t=f)
  3) placeholders + direct transmission (a=T, U=1, t=d)  <- plugin path
  4) placeholders + chunked raw RGB (a=T, U=1, f=24, m=1, ~8 chunks)
  5) placeholders created the old way (a=t, then a=p, U=1)
     -> Kitty accepts this, Ghostty is reported not to

Images are intentionally NOT deleted, so look at the terminal after the script
exits. Remove them with:  printf '\\033_Ga=d\\033\\\\'

Run inside the terminal under test (tmux needs `allow-passthrough` on).
"""

import base64
import os
import struct
import sys
import tempfile
import termios
import tty
import zlib

DIACRITICS = [
    '\u0305', '\u030D', '\u030E', '\u0310', '\u0312', '\u033D', '\u033E',
    '\u033F', '\u0346', '\u034A', '\u034B', '\u034C', '\u0350', '\u0351',
]


def make_png(path, width, height, rgba):
    row = b'\x00' + rgba * width
    raw = row * height

    def chunk(tag, data):
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', crc)

    png = (
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(raw, 9))
        + chunk(b'IEND', b'')
    )
    with open(path, 'wb') as f:
        f.write(png)
    return png


def placeholders(rows, cols):
    """U+10EEEE + diacritic(row) + diacritic(col), table is 0-indexed.

    The caller must set the cell foreground colour to the image id, that is how
    the terminal knows which image a placeholder refers to.
    """
    lines = []
    for row in range(rows):
        lines.append(''.join(
            '\U0010EEEE' + DIACRITICS[row] + DIACRITICS[col] for col in range(cols)
        ))
    return lines


def fg(image_id):
    """SGR 24-bit foreground colour carrying the image id."""
    return '\x1b[38;2;%d;%d;%dm' % (
        (image_id >> 16) & 0xFF, (image_id >> 8) & 0xFF, image_id & 0xFF,
    )


def send(out, ctrl, payload=None):
    if payload is None:
        out.write(('\x1b_G%s\x1b\\' % ctrl).encode())
    else:
        out.write(('\x1b_G%s;%s\x1b\\' % (ctrl, payload)).encode())


def send_chunked(out, first_ctrl, data, chunk_size=3072):
    offset = 0
    first = True
    while offset < len(data):
        piece = data[offset:offset + chunk_size]
        more = 1 if offset + chunk_size < len(data) else 0
        ctrl = ('%s,m=%d' % (first_ctrl, more)) if first else ('m=%d' % more)
        send(out, ctrl, base64.b64encode(piece).decode())
        offset += chunk_size
        first = False


def gradient(width, height):
    buf = bytearray()
    for y in range(height):
        for x in range(width):
            buf += bytes([(255 * x) // width, (255 * y) // height, 200])
    return bytes(buf)


def main():
    try:
        fd = os.open('/dev/tty', os.O_RDWR)
    except OSError as err:
        print('cannot open /dev/tty: %s' % err, file=sys.stderr)
        return 1

    out = os.fdopen(fd, 'wb', buffering=0)
    old = termios.tcgetattr(fd)

    path = os.path.join(tempfile.gettempdir(), 'mdmath-probe.png')
    png = make_png(path, 64, 32, bytes([255, 0, 0, 255]))
    encoded_png = base64.b64encode(png).decode()
    encoded_path = base64.b64encode(path.encode()).decode()

    try:
        tty.setraw(fd)

        out.write(b'\r\n1) plain direct PNG, no placeholders (a=T,t=d):\r\n')
        send(out, 'i=81,a=T,t=d,f=100,c=8,r=3,q=2', encoded_png)
        out.write(b'\r\n\r\n')

        out.write(b'2) placeholders + file transmission (a=T,U=1,t=f):\r\n')
        send(out, 'i=82,a=T,t=f,f=100,U=1,r=1,c=2,q=2', encoded_path)
        out.write(('\r\n' + fg(82) + placeholders(1, 2)[0] + '\x1b[39m\r\n\r\n').encode())

        out.write(b'3) placeholders + direct transmission (a=T,U=1,t=d):\r\n')
        send(out, 'i=83,a=T,t=d,f=100,U=1,r=1,c=2,q=2', encoded_png)
        out.write(('\r\n' + fg(83) + placeholders(1, 2)[0] + '\x1b[39m\r\n\r\n').encode())

        out.write(b'4) placeholders + chunked raw RGB (a=T,U=1,f=24,m=1):\r\n')
        send_chunked(out, 'i=84,a=T,t=d,f=24,U=1,r=2,c=4,s=120,v=60,q=2', gradient(120, 60))
        out.write(('\r\n' + fg(84) + '\r\n'.join(placeholders(2, 4)) + '\x1b[39m\r\n\r\n').encode())

        out.write(b'5) placeholders created separately (a=t then a=p,U=1):\r\n')
        send(out, 'i=85,a=t,t=d,f=100,q=2', encoded_png)
        send(out, 'i=85,a=p,U=1,r=1,c=2,q=2')
        out.write(('\r\n' + fg(85) + placeholders(1, 2)[0] + '\x1b[39m\r\n').encode())

        out.write(('\r\npng file used by (2): %s\r\n' % path).encode())
        out.write(b'images stay on screen; clear with: printf \'\\033_Ga=d\\033\\\\\'\r\n')
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    return 0


if __name__ == '__main__':
    sys.exit(main())
