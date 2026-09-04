#!/usr/bin/env bash
#
# generate-all-image.sh - render semua CV HTML jadi PNG (A4, maksimal 2 MB per file)
#
#   (tanpa argumen)  : render semua *.html di folder script ini
#   <file.html> ...  : render hanya file yang disebut
#   -d <dir>         : render semua *.html di folder lain
#   -m <MB>          : ubah batas ukuran per PNG (default 2)
#   -o <dir>         : folder output (default: subfolder 'png')
#
# PNG ditulis ke subfolder 'png/'. File 1 halaman -> nama.png.
# File banyak halaman -> nama-p1.png, nama-p2.png, dst.
#
# Resolusi dipilih otomatis: mulai dari 200 DPI, turun bertahap sampai hasilnya
# di bawah batas ukuran. DPI yang akhirnya dipakai ikut dilaporkan, jadi kalau
# ada file yang turun jauh, kelihatan.
#
# Sumbernya HTML, bukan PDF yang sudah ada, supaya hasilnya tidak pernah basi.
#
# Dependensi: uv. WeasyPrint, pypdfium2, dan Pillow diambil on-demand.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$SCRIPT_DIR"
OUT_DIR=""
MAX_MB="2"
FILES=()

usage() {
  echo "Usage: $(basename "$0") [-d <dir>] [-o <dir>] [-m <MB>] [file.html ...]"
  echo "  (kosong)      Render semua *.html di $SCRIPT_DIR"
  echo "  -d <dir>      Render semua *.html di <dir>"
  echo "  -o <dir>      Folder output PNG (default: <dir>/png)"
  echo "  -m <MB>       Batas ukuran per PNG (default 2)"
  echo "  file.html     Render hanya file tertentu (boleh beberapa)"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)
      [[ $# -ge 2 ]] || { echo "[ERROR] -d butuh argumen folder"; exit 1; }
      TARGET_DIR="$2"; shift 2 ;;
    -o|--out)
      [[ $# -ge 2 ]] || { echo "[ERROR] -o butuh argumen folder"; exit 1; }
      OUT_DIR="$2"; shift 2 ;;
    -m|--max-mb)
      [[ $# -ge 2 ]] || { echo "[ERROR] -m butuh angka MB"; exit 1; }
      MAX_MB="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "[ERROR] Opsi tidak dikenal: $1"; usage ;;
    *)  FILES+=("$1"); shift ;;
  esac
done

[[ -n "$OUT_DIR" ]] || OUT_DIR="$TARGET_DIR/png"

if ! command -v uv >/dev/null 2>&1; then
  export PATH="$HOME/.local/bin:$PATH"
fi
if ! command -v uv >/dev/null 2>&1; then
  echo "[ERROR] 'uv' tidak ditemukan. Install: curl -LsSf https://astral.sh/uv/install.sh | sh"
  exit 1
fi

# Varian *-ats.html dan *-photo.html adalah FILE TURUNAN dari induknya.
# Regenerate dulu supaya tidak pernah basi setelah file induk diedit.
if [[ ${#FILES[@]} -eq 0 && "$TARGET_DIR" == "$SCRIPT_DIR" ]]; then
  if [[ -f "$SCRIPT_DIR/make-ats-variants.py" ]]; then
    uv run --no-project --quiet python "$SCRIPT_DIR/make-ats-variants.py" \
      || echo "[WARN] Regenerate varian ATS gagal; melanjutkan dengan file yang ada."
  fi
  if [[ -f "$SCRIPT_DIR/make-photo-variants.py" ]]; then
    uv run --no-project --quiet --with pillow python "$SCRIPT_DIR/make-photo-variants.py" \
      || echo "[WARN] Regenerate varian foto gagal; melanjutkan dengan file yang ada."
  fi
  echo
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  [[ -d "$TARGET_DIR" ]] || { echo "[ERROR] Folder tidak ada: $TARGET_DIR"; exit 1; }
  while IFS= read -r f; do FILES+=("$f"); done < <(find "$TARGET_DIR" -maxdepth 1 -name '*.html' | sort)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "[WARN] Tidak ada file .html di $TARGET_DIR"
  exit 0
fi

mkdir -p "$OUT_DIR"
echo "Render ${#FILES[@]} file jadi PNG (maks ${MAX_MB} MB, output: $OUT_DIR)"
echo

MAX_MB="$MAX_MB" OUT_DIR="$OUT_DIR" \
uv run --no-project --quiet --with weasyprint --with pypdfium2 --with pillow \
  python - "${FILES[@]}" <<'PYEOF'
import io
import os
import sys

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

import logging
logging.getLogger("weasyprint").setLevel(logging.ERROR)
logging.getLogger("fontTools").setLevel(logging.ERROR)

import pypdfium2 as pdfium
from weasyprint import HTML

OUT_DIR = os.environ["OUT_DIR"]
MAX_BYTES = float(os.environ["MAX_MB"]) * 1024 * 1024

# Dicoba dari yang paling tajam; berhenti di DPI pertama yang muat.
DPI_LADDER = [200, 175, 150, 125, 110, 96, 80]

failed = 0
lowered = 0
written = 0


def encode(page, dpi):
    """Render satu halaman pada DPI tertentu, kembalikan (bytes_png, lebar, tinggi)."""
    img = page.render(scale=dpi / 72.0).to_pil()
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue(), img.width, img.height


for src in sys.argv[1:]:
    name = os.path.basename(src)
    stem = os.path.splitext(name)[0]

    if not os.path.isfile(src):
        print(f"[FAIL] {name} -> file tidak ditemukan")
        failed += 1
        continue

    try:
        pdf_bytes = HTML(filename=src).write_pdf()
        doc = pdfium.PdfDocument(pdf_bytes)
        n_pages = len(doc)
    except Exception as exc:                       # noqa: BLE001 - laporkan apa saja
        print(f"[FAIL] {name} -> {type(exc).__name__}: {exc}")
        failed += 1
        continue

    for i in range(n_pages):
        suffix = "" if n_pages == 1 else f"-p{i + 1}"
        out = os.path.join(OUT_DIR, f"{stem}{suffix}.png")

        data = w = h = used = None
        for dpi in DPI_LADDER:
            data, w, h = encode(doc[i], dpi)
            if len(data) <= MAX_BYTES:
                used = dpi
                break

        if used is None:                            # bahkan DPI terendah masih besar
            with open(out, "wb") as fh:
                fh.write(data)
            print(f"[WARN] {os.path.basename(out)} -> {len(data)/1024/1024:.2f} MB "
                  f"di {DPI_LADDER[-1]} DPI, masih di atas batas")
            failed += 1
            continue

        with open(out, "wb") as fh:
            fh.write(data)
        written += 1
        flag = ""
        if used != DPI_LADDER[0]:
            flag = f"  (diturunkan dari {DPI_LADDER[0]} DPI agar muat)"
            lowered += 1
        print(f"[OK]   {os.path.basename(out):40s} {w}x{h}px  "
              f"{used} DPI  {len(data)/1024/1024:.2f} MB{flag}")

print()
if failed:
    print(f"Selesai: {written} PNG dibuat, {failed} bermasalah")
    sys.exit(1)
if lowered:
    print(f"Selesai: {written} PNG dibuat, {lowered} diturunkan resolusinya agar muat batas")
    sys.exit(0)
print(f"Selesai: {written} PNG dibuat, semua pada {DPI_LADDER[0]} DPI")
PYEOF
