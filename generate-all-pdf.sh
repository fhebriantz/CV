#!/usr/bin/env bash
#
# generate-all-pdf.sh - render semua CV HTML di folder ini jadi PDF (A4, WeasyPrint)
#
#   (tanpa argumen)  : render semua *.html di folder script ini
#   <file.html> ...  : render hanya file yang disebut
#   -d <dir>         : render semua *.html di folder lain
#
# Nama PDF = nama HTML (cv-developer-1page.html -> cv-developer-1page.pdf).
# File yang namanya mengandung "1page" atau "linkedin" DIPERIKSA harus tepat 1 halaman;
# kalau lebih, ditandai [WARN] supaya kelihatan sebelum dikirim ke recruiter.
#
# Dependensi: uv (https://docs.astral.sh/uv/). WeasyPrint diambil on-demand
# lewat 'uv run --with', jadi tidak perlu install global dan tidak mengotori
# environment Python sistem.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$SCRIPT_DIR"
FILES=()

usage() {
  echo "Usage: $(basename "$0") [-d <dir>] [file.html ...]"
  echo "  (kosong)      Render semua *.html di $SCRIPT_DIR"
  echo "  -d <dir>      Render semua *.html di <dir>"
  echo "  file.html     Render hanya file tertentu (boleh beberapa)"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)
      [[ $# -ge 2 ]] || { echo "[ERROR] -d butuh argumen folder"; exit 1; }
      TARGET_DIR="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "[ERROR] Opsi tidak dikenal: $1"; usage ;;
    *)  FILES+=("$1"); shift ;;
  esac
done

# uv kadang tidak ada di PATH kalau script dijalankan dari file manager / cron
if ! command -v uv >/dev/null 2>&1; then
  export PATH="$HOME/.local/bin:$PATH"
fi
if ! command -v uv >/dev/null 2>&1; then
  echo "[ERROR] 'uv' tidak ditemukan. Install: curl -LsSf https://astral.sh/uv/install.sh | sh"
  exit 1
fi

# Varian *-ats.html dan *-photo.html adalah FILE TURUNAN dari induknya.
# Regenerate dulu supaya tidak pernah basi setelah file induk diedit.
if [[ "$TARGET_DIR" == "$SCRIPT_DIR" ]]; then
  if [[ -f "$SCRIPT_DIR/make-ats-variants.py" ]]; then
    uv run --no-project --quiet python "$SCRIPT_DIR/make-ats-variants.py" \
      || echo "[WARN] Regenerate varian ATS gagal; melanjutkan dengan file yang ada."
  fi
  if [[ -f "$SCRIPT_DIR/make-rizki-cv.py" ]]; then
    uv run --no-project --quiet python "$SCRIPT_DIR/make-rizki-cv.py" \
      || echo "[WARN] Regenerate CV Rizki gagal; melanjutkan dengan file yang ada."
  fi
  if [[ -f "$SCRIPT_DIR/make-photo-variants.py" ]]; then
    uv run --no-project --quiet --with pillow python "$SCRIPT_DIR/make-photo-variants.py" \
      || echo "[WARN] Regenerate varian foto gagal; melanjutkan dengan file yang ada."
  fi
  echo
fi

# Kumpulkan daftar file kalau tidak disebut eksplisit
if [[ ${#FILES[@]} -eq 0 ]]; then
  [[ -d "$TARGET_DIR" ]] || { echo "[ERROR] Folder tidak ada: $TARGET_DIR"; exit 1; }
  while IFS= read -r f; do FILES+=("$f"); done < <(find "$TARGET_DIR" -maxdepth 1 -name '*.html' | sort)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "[WARN] Tidak ada file .html di $TARGET_DIR"
  exit 0
fi

echo "Render ${#FILES[@]} file dengan WeasyPrint ..."
echo

# Satu proses Python untuk semua file: resolusi dependensi & startup cuma sekali.
uv run --no-project --quiet --with weasyprint python - "${FILES[@]}" <<'PYEOF'
import os
import sys

# Windows-safe kalau script ini dipakai lintas OS
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

import logging
# WeasyPrint berisik soal @page margin-box & font yang tidak ketemu; sembunyikan
logging.getLogger("weasyprint").setLevel(logging.ERROR)
logging.getLogger("fontTools").setLevel(logging.ERROR)

from weasyprint import HTML

failed = 0
warned = 0

for src in sys.argv[1:]:
    if not os.path.isfile(src):
        print(f"[FAIL] {os.path.basename(src)} -> file tidak ditemukan")
        failed += 1
        continue

    out = os.path.splitext(src)[0] + ".pdf"
    name = os.path.basename(src)

    try:
        doc = HTML(filename=src).render()
        pages = len(doc.pages)
        doc.write_pdf(out)
    except Exception as exc:                      # noqa: BLE001 - laporkan apa saja
        print(f"[FAIL] {name} -> {type(exc).__name__}: {exc}")
        failed += 1
        continue

    size_kb = os.path.getsize(out) / 1024
    label = "halaman" if pages == 1 else "halaman"

    # CV yang diklaim 1 halaman harus benar-benar 1 halaman
    lname = name.lower()
    if ("1page" in lname or "linkedin" in lname) and pages != 1:
        print(f"[WARN] {name} -> {pages} {label}, {size_kb:.0f} KB  "
              f"(harusnya 1 halaman, ada konten yang meluber)")
        warned += 1
    else:
        print(f"[OK]   {name} -> {pages} {label}, {size_kb:.0f} KB")

print()
total = len(sys.argv) - 1
if failed:
    print(f"Selesai: {total - failed}/{total} berhasil, {failed} gagal")
    sys.exit(1)
if warned:
    print(f"Selesai: {total} PDF dibuat, tapi {warned} file tidak sesuai target halaman")
    sys.exit(2)
print(f"Selesai: {total} PDF dibuat, semua sesuai target halaman")
PYEOF
