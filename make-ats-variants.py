#!/usr/bin/env python3
"""
make-ats-variants.py - bikin varian CV khusus ATS dari versi lengkap.

Versi *-full sudah satu kolom, jadi sudah dekat dengan bentuk yang disukai ATS.
Script ini menyalinnya lalu membuang hal-hal yang mengacaukan pembacaan mesin:

  1. letter-spacing dibuang.
     Ini penyebab heading terekstrak jadi "C O N TAC T" atau "E D U CAT I O N".
     ATS mencocokkan nama section secara literal, jadi heading yang terpecah
     bikin section-nya tidak terdeteksi sama sekali.

  2. Footer nomor halaman (@bottom-right) dibuang.
     Teks "Lutfi Febrianto - page 1 of 5" ikut terekstrak di setiap halaman dan
     hanya jadi sampah di mata parser.

Yang TIDAK diubah: satu kolom, tabel skill (terekstrak rapi sebagai
"LABEL isi"), dan bullet list native. Semuanya sudah aman.

Kirim varian ini ke portal yang pakai ATS (Workday, Greenhouse, Lever,
Jobstreet). Versi bersidebar tetap dipakai kalau CV-nya dibaca manusia langsung.

JANGAN edit file *-ats.html langsung; itu file turunan dan akan tertimpa.
Edit *-full.html, lalu jalankan 'generate-all-pdf'.
"""

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

HERE = os.path.dirname(os.path.abspath(__file__))

VARIANTS = {
    "cv-developer-full.html":    "cv-developer-ats.html",
    "cv-tech-lead-full.html":    "cv-tech-lead-ats.html",
    "cv-architect-pm-full.html": "cv-architect-pm-ats.html",
}

BANNER = (
    "<!-- FILE TURUNAN - JANGAN DIEDIT LANGSUNG.\n"
    "     Versi khusus ATS, dibuat oleh make-ats-variants.py dari {src}.\n"
    "     letter-spacing dan footer nomor halaman dibuang agar ekstraksi teks bersih.\n"
    "     Edit file induk itu, lalu jalankan 'generate-all-pdf'. -->\n"
)


def convert(src_name, dst_name):
    src = os.path.join(HERE, src_name)
    if not os.path.isfile(src):
        return f"[SKIP] {dst_name} -> induk {src_name} tidak ada", False

    s = io.open(src, encoding="utf-8").read()

    # 1) buang semua deklarasi letter-spacing
    s, n_ls = re.subn(r"\s*letter-spacing:\s*-?[\d.]+px;", "", s)

    # 2) buang blok footer nomor halaman di dalam @page
    s, n_ft = re.subn(
        r"\n\s*/\* WeasyPrint renders this footer[^*]*\*/"
        r"\n\s*@bottom-right \{[^}]*\}\n",
        "\n",
        s, count=1)

    # 3) tandai judulnya supaya tidak tertukar saat mengunggah
    s, n_ti = re.subn(r"(<title>.*?)(</title>)", r"\1 [ATS]\2", s, count=1)

    io.open(os.path.join(HERE, dst_name), "w", encoding="utf-8").write(
        BANNER.format(src=src_name) + s)

    return (f"[OK]   {dst_name} <- {src_name} "
            f"(letter-spacing: {n_ls} dibuang, footer: {n_ft}, title: {n_ti})"), True


def main():
    failed = 0
    for src_name, dst_name in VARIANTS.items():
        line, ok = convert(src_name, dst_name)
        print("  " + line)
        if not ok and line.startswith("[FAIL]"):
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
