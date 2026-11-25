"""Dibuja las imágenes de los botones redondos de arriba de la ventana de hermandad (UnionRoster.lua).

Sale todo a Media/ como .tga de 64x64 con transparencia (sin comprimir, origen abajo a la izquierda,
como las de los emoticonos):
  boton-calendario.tga  el icono de Calendario (hoja con cabecera roja, anillas y el día marcado)
  boton-circulo.tga     círculo blanco: el borde negro (teñido) y el brillo al pasar el ratón
  boton-brillo.tga      halo blanco del botón elegido
  boton-sombra.tga      sombra suave de los que no están elegidos (se tiñe de negro)

Las medidas del halo y la sombra van con ICON_SIZE de UnionRoster.lua (30): si cambia, cambiar aquí
SIZE y volver a lanzarlo. Solo usa Python, sin nada que instalar:
    python Tools/botones_redondos.py
"""
import math
import os
import struct

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Media")
TEX = 64          # lado de cada imagen
SS = 4            # muestras por lado de cada píxel (bordes suaves)

# Medidas en pantalla (las de UnionRoster.lua): el icono y lo que sobresalen el halo y la sombra
SIZE = 30
GLOW_PAD, SHADOW_PAD = 12, 8


def write_tga(path, pixels):
    """pixels: filas de arriba abajo, cada píxel (r, g, b, a) de 0 a 255."""
    h, w = len(pixels), len(pixels[0])
    head = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    body = bytearray()
    for row in reversed(pixels):
        for r, g, b, a in row:
            body += bytes((b, g, r, a))
    with open(path, "wb") as f:
        f.write(head + body)


def render(shade):
    """shade(x, y) -> (r, g, b, a) en 0..1, con x, y en unidades de la imagen (0..64). Media de SS x SS muestras."""
    rows = []
    for py in range(TEX):
        row = []
        for px in range(TEX):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(SS):
                for sx in range(SS):
                    r, g, b, a = shade(px + (sx + 0.5) / SS, py + (sy + 0.5) / SS)
                    # (premultiplicado para mezclar; luego se deshace)
                    acc[0] += r * a; acc[1] += g * a; acc[2] += b * a; acc[3] += a
            n = SS * SS
            a = acc[3] / n
            if a > 0:
                r, g, b = (acc[i] / n / a for i in range(3))
            else:
                r = g = b = 1.0
            row.append(tuple(max(0, min(255, round(v * 255))) for v in (r, g, b, a)))
        rows.append(row)
    return rows


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def lerp(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(a + (b - a) * t for a, b in zip(c1, c2))


def rounded_rect_dist(x, y, x0, y0, w, h, r):
    """Distancia con signo al borde de un rectángulo con esquinas redondeadas (negativa dentro)."""
    cx, cy = x0 + w / 2, y0 + h / 2
    qx, qy = abs(x - cx) - (w / 2 - r), abs(y - cy) - (h / 2 - r)
    outside = math.hypot(max(qx, 0), max(qy, 0))
    return outside + min(max(qx, qy), 0) - r


# ---------------------------------------------------------------------------
# Calendario: las mismas formas que la vista previa que eligió Jorge (24/11)
# ---------------------------------------------------------------------------
BG_TOP, BG_BOTTOM = hex_rgb("#5b4630"), hex_rgb("#241810")
PAGE_TOP, PAGE_BOTTOM = hex_rgb("#f3e3bd"), hex_rgb("#c9ae7c")
HEAD_TOP, HEAD_BOTTOM = hex_rgb("#d0302a"), hex_rgb("#7c1410")
INK, RING, RING_INK = hex_rgb("#2a1a0c"), hex_rgb("#d9b25a"), hex_rgb("#3a260c")
CELL, TODAY = hex_rgb("#7a5a34"), hex_rgb("#c0281e")
CELLS = [(17, 31, 6, 5), (26, 31, 6, 5), (35, 31, 6, 5), (44, 31, 5, 5),
         (17, 40, 6, 5), (35, 40, 6, 5), (44, 40, 5, 5)]


def shape(color, d, stroke=None, width=0.0):
    """El color de una figura en un punto: trazo centrado en el borde por encima del relleno (como en SVG)."""
    if stroke and abs(d) <= width / 2:
        return stroke
    if d <= 0:
        return color
    return None


def calendar(x, y):
    c = lerp(BG_TOP, BG_BOTTOM, y / TEX)
    layers = [
        shape(lerp(PAGE_TOP, PAGE_BOTTOM, (y - 15) / 38), rounded_rect_dist(x, y, 12, 15, 40, 38, 3), INK, 2),
        shape(lerp(HEAD_TOP, HEAD_BOTTOM, (y - 15) / 11), rounded_rect_dist(x, y, 12, 15, 40, 11, 3), INK, 2),
        shape(RING, rounded_rect_dist(x, y, 20, 10, 4, 10, 2), RING_INK, 1),
        shape(RING, rounded_rect_dist(x, y, 40, 10, 4, 10, 2), RING_INK, 1),
    ]
    layers += [shape(CELL, rounded_rect_dist(x, y, cx, cy, w, h, 0)) for cx, cy, w, h in CELLS]
    layers.append(shape(TODAY, rounded_rect_dist(x, y, 26, 40, 6, 5, 0)))
    for col in layers:
        if col is not None:
            c = col
    return (*c, 1.0)


# ---------------------------------------------------------------------------
# Círculo, halo y sombra (blancos: el juego los tiñe con SetVertexColor)
# ---------------------------------------------------------------------------
def circle(x, y):
    r = math.hypot(x - TEX / 2, y - TEX / 2)
    return (1.0, 1.0, 1.0, 1.0 if r <= TEX / 2 - 0.5 else 0.0)


def soft_ring(pad, spread, blur, alpha):
    """Como un box-shadow de CSS alrededor de un círculo de SIZE: se ve desde el borde del icono hacia fuera."""
    shown = SIZE + 2 * pad              # lo que mide la imagen en pantalla
    k = shown / TEX                     # píxeles de pantalla por píxel de la imagen

    def shade(x, y):
        out = math.hypot(x - TEX / 2, y - TEX / 2) * k - SIZE / 2   # cuánto fuera del icono (en pantalla)
        sigma = blur / 2
        a = alpha * 0.5 * math.erfc((out - spread) / (sigma * math.sqrt(2)))
        # (en el borde de la imagen, a cero: que no se vea el corte)
        edge = SIZE / 2 + pad
        fade = max(0.0, min(1.0, (edge - (out + SIZE / 2)) / 1.5))
        return (1.0, 1.0, 1.0, a * fade)
    return shade


def main():
    os.makedirs(OUT, exist_ok=True)
    jobs = {
        "boton-calendario": calendar,
        "boton-circulo": circle,
        # (elegido: «0 0 9px 3px» blanco al 67 %, el de la vista previa)
        "boton-brillo": soft_ring(GLOW_PAD, 3, 9, 0.67),
        # (sin elegir: «0 2px 4px» negro al 60 %; los 2 px hacia abajo los pone el juego)
        "boton-sombra": soft_ring(SHADOW_PAD, 0, 4, 0.6),
    }
    for name, fn in jobs.items():
        path = os.path.join(OUT, name + ".tga")
        write_tga(path, render(fn))
        print("ok", os.path.normpath(path))


if __name__ == "__main__":
    main()
