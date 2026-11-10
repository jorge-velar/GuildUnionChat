#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Guild Union - emoticonos de un canal de Twitch (BTTV, FrankerFaceZ y 7TV)

El juego no deja a un addon conectarse a internet, así que los emoticonos se bajan
con este programa (fuera del juego), se guardan como imágenes .tga dentro de la
carpeta del addon y te da las líneas para pegar en
Configuración > Chat > Importar emoticonos (solo el maestro).

Uso (con Python 3 y la librería Pillow:  pip install pillow):
    python emoticonos_twitch.py NOMBRE_DEL_CANAL
    python emoticonos_twitch.py NOMBRE_DEL_CANAL --max 80 --global

Opciones:
    --max N           como mucho N emoticonos (por defecto 150, el máximo del addon)
    --global          añade también los globales de BTTV (PepeLaugh, monkaS...)
    --client-id ID --token TOKEN
                      (opcional) también los emoticonos propios de Twitch del canal
                      (suscripción); hace falta una app de Twitch: dev.twitch.tv

IMPORTANTE: las imágenes tienen que estar en el ordenador de TODOS los jugadores.
Después de bajarlas, vuelve a repartir la carpeta GuildUnion entera (con Media\\Twitch)
a todo el mundo; si no, a quien no las tenga le saldrá un cuadro en su lugar.
"""
import argparse, io, json, os, re, sys, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)                      # ...\Interface\AddOns\GuildUnion
OUT = os.path.join(ADDON, "Media", "Twitch")
WOW_PATH = "Interface\\AddOns\\" + os.path.basename(ADDON) + "\\Media\\Twitch\\"
UA = {"User-Agent": "GuildUnion-emotes/1.0"}

def get_json(url, headers=None):
    req = urllib.request.Request(url, headers=dict(UA, **(headers or {})))
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode("utf-8"))

def get_bytes(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read()

def twitch_id(login):
    req = urllib.request.Request("https://decapi.me/twitch/id/" + login, headers=UA)
    with urllib.request.urlopen(req, timeout=20) as r:
        txt = r.read().decode("utf-8").strip()
    if not txt.isdigit():
        raise SystemExit("No encuentro el canal de Twitch '%s' (%s)" % (login, txt))
    return txt

def bttv(uid, include_global):
    out = []
    try:
        d = get_json("https://api.betterttv.net/3/cached/users/twitch/" + uid)
        for e in d.get("channelEmotes", []) + d.get("sharedEmotes", []):
            out.append((e["code"], "https://cdn.betterttv.net/emote/%s/2x" % e["id"]))
    except Exception as ex:
        print("  (BTTV: %s)" % ex)
    if include_global:
        try:
            for e in get_json("https://api.betterttv.net/3/cached/emotes/global"):
                out.append((e["code"], "https://cdn.betterttv.net/emote/%s/2x" % e["id"]))
        except Exception as ex:
            print("  (BTTV global: %s)" % ex)
    return out

def ffz(login):
    out = []
    try:
        d = get_json("https://api.frankerfacez.com/v1/room/" + login)
        for s in d.get("sets", {}).values():
            for e in s.get("emoticons", []):
                urls = e.get("urls", {})
                u = urls.get("2") or urls.get("1") or urls.get("4")
                if u:
                    out.append((e["name"], ("https:" + u) if u.startswith("//") else u))
    except Exception as ex:
        print("  (FFZ: %s)" % ex)
    return out

def seventv(uid):
    out = []
    try:
        d = get_json("https://7tv.io/v3/users/twitch/" + uid)
        for e in (d.get("emote_set") or {}).get("emotes", []):
            host = e["data"]["host"]["url"]
            out.append((e["name"], "https:" + host + "/2x.png"))
    except Exception as ex:
        print("  (7TV: %s)" % ex)
    return out

def twitch_native(uid, client_id, token):
    out = []
    try:
        d = get_json("https://api.twitch.tv/helix/chat/emotes?broadcaster_id=" + uid,
                     {"Client-Id": client_id, "Authorization": "Bearer " + token})
        tpl = d.get("template", "")
        for e in d.get("data", []):
            u = tpl.replace("{{id}}", e["id"]).replace("{{format}}", "static").replace("{{theme_mode}}", "dark").replace("{{scale}}", "2.0")
            out.append((e["name"], u))
    except Exception as ex:
        print("  (Twitch: %s)" % ex)
    return out

def to_tga(data, path):
    from PIL import Image
    im = Image.open(io.BytesIO(data))
    try:
        im.seek(0)          # animados: el primer fotograma (el juego no anima texturas)
    except Exception:
        pass
    im = im.convert("RGBA")
    # el juego quiere tamaños potencia de 2: 32x32 (centrado, sin deformar)
    im.thumbnail((32, 32), Image.LANCZOS)
    canvas = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    canvas.paste(im, ((32 - im.width) // 2, (32 - im.height) // 2))
    canvas.save(path, format="TGA", compression=None)

def main():
    ap = argparse.ArgumentParser(description="Emoticonos de Twitch para Guild Union")
    ap.add_argument("canal", nargs="*", help="uno o varios canales de Twitch")
    ap.add_argument("--max", type=int, default=150)
    ap.add_argument("--global", dest="glob", action="store_true")
    ap.add_argument("--client-id")
    ap.add_argument("--token")
    a = ap.parse_args()
    canales = [c.strip().lower() for c in a.canal if c.strip()]
    if not canales:
        txt = input("Nombre del canal de Twitch (si son varios, separados por espacios): ")
        canales = [c.strip().lower() for c in txt.replace(",", " ").split() if c.strip()]
    if not canales:
        raise SystemExit("No has escrito ningún canal.")
    login = "_".join(canales)
    try:
        import PIL  # noqa
    except ImportError:
        raise SystemExit("Falta la librería Pillow. Instálala con:  pip install pillow")
    found = []
    for canal in canales:
        print("Canal:", canal)
        uid = twitch_id(canal)
        if a.client_id and a.token:
            found += twitch_native(uid, a.client_id, a.token)
        found += seventv(uid) + bttv(uid, a.glob) + ffz(canal)
    os.makedirs(OUT, exist_ok=True)
    lines, seen = [], set()
    for code, url in found:
        # códigos sin espacios ni símbolos raros (el addon los busca como palabras)
        if not re.fullmatch(r"[A-Za-z0-9_:()\-]{2,20}", code) or code in seen:
            continue
        fname = re.sub(r"[^A-Za-z0-9_]", "_", code)
        if fname.lower() in {s.lower() for s in seen}:
            fname += "_%d" % len(seen)
        try:
            to_tga(get_bytes(url), os.path.join(OUT, fname + ".tga"))
        except Exception as ex:
            print("  no se pudo bajar %s (%s)" % (code, ex))
            continue
        seen.add(code)
        lines.append("%s=%s%s" % (code, WOW_PATH, fname))
        print("  ok", code)
        if len(lines) >= a.max:
            break
    txt = os.path.join(HERE, "emoticonos_%s.txt" % login)
    with open(txt, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    # el "pack": el addon lo lee al cargar y el maestro lo activa con un clic en el juego
    def lua(s): return s.replace("\\", "\\\\").replace('"', '\\"')
    with open(os.path.join(ADDON, "EmotePack.lua"), "w", encoding="utf-8") as f:
        f.write("-- Guild Union - pack de emoticonos de Twitch (lo crea Tools\\emoticonos_twitch.py)\n")
        f.write("local _, HU = ...\n")
        f.write('HU.EMOTE_PACK = { channel = "%s", list = {\n' % lua(", ".join(canales)))
        for l in lines:
            code, path = l.split("=", 1)
            f.write('    { "%s", "%s" },\n' % (lua(code), lua(path)))
        f.write("} }\n")
    print("\n%d emoticonos guardados en %s" % (len(lines), OUT))
    print("Las líneas (por si las quieres pegar a mano) están en:", txt)
    print()
    print("LISTO. Ahora:")
    print("  1) Comprime la carpeta GuildUnion entera y repártela a todos (como una versión nueva del addon).")
    print("  2) Todos cierran y abren el juego (con /reload no se cargan imágenes nuevas).")
    print("  3) Un maestro: Configuración > Chat > Importar > 'Añadir el pack de Twitch' > Guardar para todos.")

if __name__ == "__main__":
    main()
