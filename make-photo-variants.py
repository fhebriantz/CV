#!/usr/bin/env python3
"""
make-photo-variants.py - bikin varian CV berfoto dari file induk tanpa foto.

Untuk tiap CV 1 halaman, script ini menyalin file induknya, mengganti lingkaran
monogram "LF" dengan headshot yang di-crop, lalu menulisnya sebagai *-photo.html.

Kenapa ada script ini: varian berfoto adalah FILE TURUNAN. Kalau dibuat manual,
setiap kali file induk diedit varian fotonya jadi basi tanpa ketahuan (sudah tiga
kali kejadian). generate-all-pdf.sh memanggil script ini lebih dulu supaya
varian foto selalu ikut versi terbaru induknya.

JANGAN edit file *-photo.html langsung. Edit induknya, lalu jalankan
'generate-all-pdf'. Perubahan di *-photo.html akan tertimpa.

Foto ditanam sebagai data URI base64, bukan <img src="foto.jpg">, supaya file
HTML-nya tetap bisa dipindah atau dikirim sendirian tanpa fotonya hilang.

Menyesuaikan crop: ubah CX / HAIR_TOP / SIZE di bawah.
  CX        titik tengah kepala (px, dari kiri). Naikkan -> kepala geser ke kiri.
  HAIR_TOP  posisi puncak rambut (px, dari atas).
  SIZE      sisi kotak crop (px). Besarkan -> wajah mengecil, lebih banyak bahu.
Cara andal mengeceknya: render lingkaran + garis tengah vertikal, lalu nilai
simetri wajah terhadap garis itu. Menebak dari mata sering meleset.
"""

import base64
import io
import os
import re
import sys

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

from PIL import Image

# ---------------------------------------------------------------- konfigurasi

HERE = os.path.dirname(os.path.abspath(__file__))

# Kandidat file foto sumber, dipakai yang pertama ketemu.
PHOTO_CANDIDATES = [
    "foto-source.png",
    "foto-source.jpg",
    "Gemini_Generated_Image_feavmyfeavmyfeav.png",
]

CX, HAIR_TOP, SIZE = 436, 180, 470   # parameter crop (lihat docstring)
OUT_PX = 600                          # cetak 28mm butuh ~330px; 600 = 2x, aman
JPEG_QUALITY = 85

# induk -> turunan
VARIANTS = {
    "cv-developer-1page.html":    "cv-developer-1page-photo.html",
    "cv-tech-lead-1page.html":    "cv-tech-lead-1page-photo.html",
    "cv-tech-lead-linkedin.html": "cv-tech-lead-linkedin-photo.html",
    "cv-architect-pm-1page.html": "cv-architect-pm-1page-photo.html",
}

BANNER = (
    "<!-- FILE TURUNAN - JANGAN DIEDIT LANGSUNG.\n"
    "     Dibuat oleh make-photo-variants.py dari {src}.\n"
    "     Edit file induk itu, lalu jalankan 'generate-all-pdf'. -->\n"
)

# ---------------------------------------------------------------- proses


def find_photo():
    for name in PHOTO_CANDIDATES:
        path = os.path.join(HERE, name)
        if os.path.isfile(path):
            return path
    return None


def build_headshot(path):
    """Crop kotak di sekitar kepala, kecilkan, kembalikan (base64, ukuran KB)."""
    im = Image.open(path).convert("RGB")
    top = int(HAIR_TOP - 0.09 * SIZE)          # headroom ~9% dari tinggi frame
    half = SIZE // 2
    crop = im.crop((CX - half, top, CX + half, top + SIZE))
    crop = crop.resize((OUT_PX, OUT_PX), Image.LANCZOS)

    # simpan juga sebagai file terpisah; berguna untuk foto profil LinkedIn
    crop.save(os.path.join(HERE, "foto-headshot.jpg"), "JPEG",
              quality=JPEG_QUALITY, optimize=True, progressive=True)

    buf = io.BytesIO()
    crop.save(buf, "JPEG", quality=JPEG_QUALITY, optimize=True, progressive=True)
    return base64.b64encode(buf.getvalue()).decode(), len(buf.getvalue()) / 1024


def make_variant(src_name, dst_name, b64):
    src = os.path.join(HERE, src_name)
    if not os.path.isfile(src):
        return f"[SKIP] {dst_name} -> induk {src_name} tidak ada"

    s = io.open(src, encoding="utf-8").read()

    # ukuran lingkaran diambil dari .monogram supaya foto persis menggantikannya
    m = re.search(
        r"\.monogram\s*\{\s*\n?\s*width:\s*([\d.]+)mm;\s*height:\s*([\d.]+)mm;"
        r"\s*margin:\s*0 auto ([\d.]+)mm;", s)
    if not m:
        return f"[FAIL] {dst_name} -> blok .monogram tidak dikenali di {src_name}"
    w, h, mb = m.groups()

    s, n1 = re.subn(
        r"  /\* Swap in a real photo:.*?\*/",
        (f"  .photo {{\n"
         f"    width: {w}mm; height: {h}mm; margin: 0 auto {mb}mm;\n"
         f"    display: block; border-radius: 50%; object-fit: cover;\n"
         f"  }}"),
        s, count=1, flags=re.S)

    s, n2 = re.subn(
        r'<div class="monogram">LF</div>',
        f'<img class="photo" src="data:image/jpeg;base64,{b64}" alt="Lutfi Febrianto">',
        s, count=1)

    if n1 != 1 or n2 != 1:
        return f"[FAIL] {dst_name} -> css={n1} html={n2} (harusnya 1/1)"

    io.open(os.path.join(HERE, dst_name), "w", encoding="utf-8").write(
        BANNER.format(src=src_name) + s)
    return f"[OK]   {dst_name} <- {src_name} (foto {w}mm)"


def main():
    photo = find_photo()
    if photo is None:
        print("[WARN] Foto sumber tidak ada, varian *-photo.html dilewati.")
        print("       Taruh foto sebagai 'foto-source.jpg' di folder ini.")
        return 0

    b64, kb = build_headshot(photo)
    print(f"Headshot dari {os.path.basename(photo)}: "
          f"{OUT_PX}x{OUT_PX}, {kb:.0f} KB (crop cx={CX} size={SIZE})")

    failed = 0
    for src_name, dst_name in VARIANTS.items():
        line = make_variant(src_name, dst_name, b64)
        print("  " + line)
        if line.startswith("[FAIL]"):
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
