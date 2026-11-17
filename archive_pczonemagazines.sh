# 1. Create the file with a heredoc (paste this whole block at once)
cat > ~/pczone.sh <<'EOF'
#!/bin/bash
set -euo pipefail

BASE="https://archive.org/download/pczone-magazine-complete-collection"
DEST="$HOME/Downloads/pczone"
mkdir -p "$DEST"
cd "$DEST"

files=(
  "PC_Zone_Issue_1__April_1993__flipbook.zip"
  "PC_Zone_Issue_2__May_1993__flipbook.zip"
  "PC_Zone_Issue_3__June_1993__flipbook.zip"
  "PC_Zone_Issue_4__July_1993__flipbook.zip"
  "PC_Zone_Issue_5__August_1993__flipbook.zip"
  "PC_Zone_Issue_6__September_1993__flipbook.zip"
  "PC_Zone_Issue_7__October_1993__flipbook.zip"
  "PC_Zone_Issue_8__November_1993__flipbook.zip"
  "PC_Zone_Issue_9__December_1993__flipbook.zip"
  "PC_Zone_Issue_10__January_1994__flipbook.zip"
  "PC_Zone_Issue_11__February_1994__flipbook.zip"
  "PC_Zone_Issue_12__March_1994__flipbook.zip"
  "PC_Zone_Issue_13__April_1994__flipbook.zip"
  "PC_Zone_Issue_14__May_1994__flipbook.zip"
  "PC_Zone_Issue_15__June_1994__flipbook.zip"
  "PC_Zone_Issue_16__July_1994__flipbook.zip"
  "PC_Zone_Issue_17__August_1994__flipbook.zip"
  "PC_Zone_Issue_18__September_1994__flipbook.zip"
  "PC_Zone_Issue_19__October_1994__flipbook.zip"
  "PC_Zone_Issue_20__November_1994__flipbook.zip"
  "PC_Zone_Issue_21__December_1994__flipbook.zip"
  "PC_Zone_Issue_22__January_1995__flipbook.zip"
  "PC_Zone_Issue_23__February_1995__flipbook.zip"
  "PC_Zone_Issue_24__March_1995__flipbook.zip"
  "PC_Zone_Issue_25__April_1995__flipbook.zip"
  "PC_Zone_Issue_26__May_1995__flipbook.zip"
  "PC_Zone_Issue_27__June_1995__flipbook.zip"
  "PC_Zone_Issue_28__July_1995__flipbook.zip"
  "PC_Zone_Issue_29__August_1995__flipbook.zip"
  "PC_Zone_Issue_30__September_1995__flipbook.zip"
  "PC_Zone_Issue_31__October_1995__flipbook.zip"
  "PC_Zone_Issue_32__November_1995__flipbook.zip"
  "PC_Zone_Issue_33__December_1995__flipbook.zip"
  "PC_Zone_Issue_34__January_1996__flipbook.zip"
  "PC_Zone_Issue_35__February_1996__flipbook.zip"
  "PC_Zone_Issue_36__March_1996__flipbook.zip"
  "PC_Zone_Issue_37__April_1996__flipbook.zip"
  "PC_Zone_Issue_38__May_1996__flipbook.zip"
  "PC_Zone_Issue_39__June_1996__flipbook.zip"
  "PC_Zone_Issue_40__July_1996__flipbook.zip"
  "PC_Zone_Issue_41__August_1996__flipbook.zip"
  "PC_Zone_Issue_42__September_1996__flipbook.zip"
  "PC_Zone_Issue_43__October_1996__flipbook.zip"
  "PC_Zone_Issue_44__November_1996__flipbook.zip"
  "PC_Zone_Issue_45__December_1996__flipbook.zip"
  "PC_Zone_Issue_46__January_1997__flipbook.zip"
  "PC_Zone_Issue_47__February_1997__flipbook.zip"
  "PC_Zone_Issue_48__March_1997__flipbook.zip"
  "PC_Zone_Issue_49__April_1997__flipbook.zip"
  "PC_Zone_Issue_50__May_1997__flipbook.zip"
  "PC_Zone_Issue_51__June_1997__flipbook.zip"
  "PC_Zone_Issue_52__July_1997__flipbook.zip"
  "PC_Zone_Issue_53__August_1997__flipbook.zip"
  "PC_Zone_Issue_54__September_1997__flipbook.zip"
  "PC_Zone_Issue_55__October_1997__flipbook.zip"
  "PC_Zone_Issue_56__November_1997__flipbook.zip"
  "PC_Zone_Issue_57__December_1997__flipbook.zip"
  "PC_Zone_Issue_58__Xmas_1997__flipbook.zip"
  "PC_Zone_Issue_59__January_1998__flipbook.zip"
  "PC_Zone_Issue_60__February_1998__flipbook.zip"
  "PC_Zone_Issue_61__March_1998__flipbook.zip"
  "PC_Zone_Issue_62__April_1998__flipbook.zip"
  "PC_Zone_Issue_63__May_1998__flipbook.zip"
  "PC_Zone_Issue_64__June_1998__flipbook.zip"
  "PC_Zone_Issue_65__July_1998__flipbook.zip"
  "PC_Zone_Issue_66__August_1998__flipbook.zip"
  "PC_Zone_Issue_67__September_1998__flipbook.zip"
  "PC_Zone_Issue_68__October_1998__flipbook.zip"
  "PC_Zone_Issue_69__November_1998__flipbook.zip"
  "PC_Zone_Issue_70__December_1998__flipbook.zip"
  "PC_Zone_Issue_71__Xmas_1998__flipbook.zip"
  "PC_Zone_Issue_72__January_1999__flipbook.zip"
  "PC_Zone_Issue_73__February_1999__flipbook.zip"
  "PC_Zone_Issue_74__March_1999__flipbook.zip"
  "PC_Zone_Issue_75__April_1999__flipbook.zip"
  "PC_Zone_Issue_76__May_1999__flipbook.zip"
  "PC_Zone_Issue_77__June_1999__flipbook.zip"
  "PC_Zone_Issue_78__July_1999__flipbook.zip"
  "PC_Zone_Issue_79__August_1999__flipbook.zip"
  "PC_Zone_Issue_80__September_1999__flipbook.zip"
  "PC_Zone_Issue_81__October_1999__flipbook.zip"
  "PC_Zone_Issue_82__November_1999__flipbook.zip"
  "PC_Zone_Issue_83__December_1999__flipbook.zip"
  "PC_Zone_Issue_84__Xmas_1999__flipbook.zip"
  "PC_Zone_Issue_85__January_2000__flipbook.zip"
  "PC_Zone_Issue_86__February_2000__flipbook.zip"
  "PC_Zone_Issue_87__March_2000__flipbook.zip"
  "PC_Zone_Issue_88__April_2000__flipbook.zip"
  "PC_Zone_Issue_89__May_2000__flipbook.zip"
  "PC_Zone_Issue_90__June_2000__flipbook.zip"
  "PC_Zone_Issue_91__July_2000__flipbook.zip"
  "PC_Zone_Issue_92__August_2000__flipbook.zip"
  "PC_Zone_Issue_93__September_2000__flipbook.zip"
  "PC_Zone_Issue_94__October_2000__flipbook.zip"
  "PC_Zone_Issue_95__November_2000__flipbook.zip"
  "PC_Zone_Issue_96__December_2000__flipbook.zip"
  "PC_Zone_Issue_97__Xmas_2000__flipbook.zip"
  "PC_Zone_Issue_98__January_2001__flipbook.zip"
  "PC_Zone_Issue_99__February_2001__flipbook.zip"
  "PC_Zone_Issue_100__March_2001__flipbook.zip"
  "PC_Zone_Issue_101__April_2001__flipbook.zip"
  "PC_Zone_Issue_102__May_2001__flipbook.zip"
  "PC_Zone_Issue_103__June_2001__flipbook.zip"
  "PC_Zone_Issue_104__July_2001__flipbook.zip"
  "PC_Zone_Issue_105__August_2001__flipbook.zip"
  "PC_Zone_Issue_106__September_2001__flipbook.zip"
  "PC_Zone_Issue_107__October_2001__flipbook.zip"
  "PC_Zone_Issue_108__November_2001__flipbook.zip"
  "PC_Zone_Issue_109__December_2001__flipbook.zip"
  "PC_Zone_Issue_110__Xmas_2001__flipbook.zip"
  "PC_Zone_Issue_111__January_2002__flipbook.zip"
  "PC_Zone_Issue_112__February_2002__flipbook.zip"
  "PC_Zone_Issue_113__March_2002__flipbook.zip"
  "PC_Zone_Issue_114__April_2002__flipbook.zip"
  "PC_Zone_Issue_115__May_2002__flipbook.zip"
  "PC_Zone_Issue_116__June_2002__flipbook.zip"
  "PC_Zone_Issue_117__July_2002__flipbook.zip"
  "PC_Zone_Issue_118__August_2002__flipbook.zip"
  "PC_Zone_Issue_119__September_2002__flipbook.zip"
  "PC_Zone_Issue_120__October_2002__flipbook.zip"
  "PC_Zone_Issue_121__November_2002__flipbook.zip"
  "PC_Zone_Issue_122__December_2002__flipbook.zip"
  "PC_Zone_Issue_123__Christmas_2002__flipbook.zip"
  "PC_Zone_Issue_124__January_2003__flipbook.zip"
  "PC_Zone_Issue_125__February_2003__flipbook.zip"
  "PC_Zone_Issue_126__March_2003__flipbook.zip"
  "PC_Zone_Issue_127__April_2003__flipbook.zip"
  "PC_Zone_Issue_128__May_2003__flipbook.zip"
  "PC_Zone_Issue_129__June_2003__flipbook.zip"
  "PC_Zone_Issue_130__July_2003__flipbook.zip"
  "PC_Zone_Issue_131__August_2003__flipbook.zip"
  "PC_Zone_Issue_132__September_2003__flipbook.zip"
  "PC_Zone_Issue_133__October_2003__flipbook.zip"
  "PC_Zone_Issue_134__November_2003__flipbook.zip"
  "PC_Zone_Issue_135__December_2003__flipbook.zip"
  "PC_Zone_Issue_136__Christmas_2003__flipbook.zip"
  "PC_Zone_Issue_137__January_2004__flipbook.zip"
  "PC_Zone_Issue_138__February_2004__flipbook.zip"
  "PC_Zone_Issue_139__March_2004__flipbook.zip"
  "PC_Zone_Issue_140__April_2004__flipbook.zip"
  "PC_Zone_Issue_141__May_2004__flipbook.zip"
  "PC_Zone_Issue_142__June_2004__flipbook.zip"
  "PC_Zone_Issue_143__July_2004__flipbook.zip"
  "PC_Zone_Issue_144__August_2004__flipbook.zip"
  "PC_Zone_Issue_145__September_2004__flipbook.zip"
  "PC_Zone_Issue_146__October_2004__flipbook.zip"
  "PC_Zone_Issue_147__November_2004__flipbook.zip"
  "PC_Zone_Issue_148__December_2004__flipbook.zip"
  "PC_Zone_Issue_149__Xmas_2004__flipbook.zip"
  "PC_Zone_Issue_150__January_2005__flipbook.zip"
  "PC_Zone_Issue_151__February_2005__flipbook.zip"
  "PC_Zone_Issue_152__March_2005__flipbook.zip"
  "PC_Zone_Issue_153__April_2005__flipbook.zip"
  "PC_Zone_Issue_154__May_2005__flipbook.zip"
  "PC_Zone_Issue_155__June_2005__flipbook.zip"
  "PC_Zone_Issue_156__July_2005__flipbook.zip"
  "PC_Zone_Issue_157__Aug_2005__flipbook.zip"
  "PC_Zone_Issue_158__September_2005__flipbook.zip"
  "PC_Zone_Issue_159__October_2005__flipbook.zip"
  "PC_Zone_Issue_160__November_2005__flipbook.zip"
  "PC_Zone_Issue_161__December_2005__flipbook.zip"
  "PC_Zone_Issue_162__Christmas_2005__flipbook.zip"
  "PC_Zone_Issue_163__January_2006__flipbook.zip"
  "PC_Zone_Issue_164__February_2006__flipbook.zip"
  "PC_Zone_Issue_165__March_2006__flipbook.zip"
  "PC_Zone_Issue_166__April_2006__flipbook.zip"
  "PC_Zone_Issue_167__May_2006__flipbook.zip"
  "PC_Zone_Issue_168__June_2006__flipbook.zip"
  "PC_Zone_Issue_169__July_2006__flipbook.zip"
  "PC_Zone_Issue_170__August_2006__flipbook.zip"
  "PC_Zone_Issue_171__September_2006__flipbook.zip"
  "PC_Zone_Issue_172__October_2006__flipbook.zip"
  "PC_Zone_Issue_173__November_2006__flipbook.zip"
  "PC_Zone_Issue_174__December_2006__flipbook.zip"
  "PC_Zone_Issue_175__Christmas_2006__flipbook.zip"
  "PC_Zone_Issue_176__January_2007__flipbook.zip"
  "PC_Zone_Issue_177__February_2007__flipbook.zip"
  "PC_Zone_Issue_178__March_2007__flipbook.zip"
  "PC_Zone_Issue_179__April_2007__flipbook.zip"
  "PC_Zone_Issue_180__May_2007__flipbook.zip"
  "PC_Zone_Issue_181__June_2007__flipbook.zip"
  "PC_Zone_Issue_182__July_2007__flipbook.zip"
  "PC_Zone_Issue_183__August_2007__flipbook.zip"
  "PC_Zone_Issue_184__September_2007__flipbook.zip"
  "PC_Zone_Issue_185__October_2007__flipbook.zip"
  "PC_Zone_Issue_186__November_2007__flipbook.zip"
  "PC_Zone_Issue_187__December_2007__flipbook.zip"
  "PC_Zone_Issue_188__Xmas_2007__flipbook.zip"
  "PC_Zone_Issue_189__Jan_2008__flipbook.zip"
  "PC_Zone_Issue_190__February_2008__flipbook.zip"
  "PC_Zone_Issue_191__March_2008__flipbook.zip"
  "PC_Zone_Issue_192__April_2008__flipbook.zip"
  "PC_Zone_Issue_193__May_2008__flipbook.zip"
  "PC_Zone_Issue_194__June_2008__flipbook.zip"
  "PC_Zone_Issue_195__July_2008__flipbook.zip"
  "PC_Zone_Issue_196__August_2008__flipbook.zip"
  "PC_Zone_Issue_197__September_2008__flipbook.zip"
  "PC_Zone_Issue_198__Octber_2008__flipbook.zip"
  "PC_Zone_Issue_199__November_2008__flipbook.zip"
  "PC_Zone_Issue_200__December_2008__flipbook.zip"
  "PC_Zone_Issue_201__Xmas_2008__flipbook.zip"
  "PC_Zone_Issue_202__January_2009__flipbook.zip"
  "PC_Zone_Issue_203__February_2009__flipbook.zip"
  "PC_Zone_Issue_204__March_2009__flipbook.zip"
  "PC_Zone_Issue_205__April_2009__flipbook.zip"
  "PC_Zone_Issue_206__May_2009__flipbook.zip"
  "PC_Zone_Issue_207__June_2009__flipbook.zip"
  "PC_Zone_Issue_208__July_2009__flipbook.zip"
  "PC_Zone_Issue_209__August_2009__flipbook.zip"
  "PC_Zone_Issue_210__September_2009__flipbook.zip"
  "PC_Zone_Issue_211__October_2009__flipbook.zip"
  "PC_Zone_Issue_212__November_2009__flipbook.zip"
  "PC_Zone_Issue_213__December_2009__flipbook.zip"
  "PC_Zone_Issue_214__Xmas_2009__flipbook.zip"
  "PC_Zone_Issue_215__January_2010__flipbook.zip"
  "PC_Zone_Issue_216__February_2010__flipbook.zip"
  "PC_Zone_Issue_217__March_2010__flipbook.zip"
  "PC_Zone_Issue_218__April_2010__flipbook.zip"
  "PC_Zone_Issue_219__May_2010__flipbook.zip"
  "PC_Zone_Issue_220__June_2010__flipbook.zip"
  "PC_Zone_Issue_221__July_2010__flipbook.zip"
  "PC_Zone_Issue_222__August_2010__flipbook.zip"
  "PC_Zone_Issue_223__September_2010__flipbook.zip"
  "PC_Zone_Issue_224__October_2010__flipbook.zip"
  "PC_Zone_Issue_225__November_2010__flipbook.zip"
  "manifest.json"
  "pczone-magazine-complete-collection_archive.torrent"
  "pczone-magazine-complete-collection_files.xml"
  "pczone-magazine-complete-collection_meta.sqlite"
  "pczone-magazine-complete-collection_meta.xml"
)

# ---- main loop ----
total=${#files[@]}
i=0
for f in "${files[@]}"; do
  i=$((i+1))
  printf '[%d/%d] %s\n' "$i" "$total" "$f"

  # --- download (resume-friendly, skip if already present) ---
  if [[ ! -f "$f" ]]; then
    if ! curl -L --fail --retry 5 --retry-delay 3 -C - -o "$f" "$BASE/$f"; then
      echo "!! DOWNLOAD FAILED: $f (continuing)" >&2
      continue
    fi
  fi

  # --- non-zip files: leave them alone ---
  if [[ "$f" != *.zip ]]; then
    continue
  fi

  # --- extract zip into a temp dir ---
  tmpdir=".__extracting__"
  rm -rf "$tmpdir"
  mkdir -p "$tmpdir"

  echo "   extracting..."
  if ! unzip -q -o "$f" -d "$tmpdir"; then
    echo "!! UNZIP FAILED: $f (zip kept, temp dir kept)" >&2
    continue
  fi
  rm -f "$f"

  # --- find the main HTML (index.html first, else the largest .html) ---
  html=""
  if [[ -f "$tmpdir/index.html" ]]; then
    html="$tmpdir/index.html"
  else
    html=$(find "$tmpdir" -maxdepth 2 -type f -iname '*.html' -print0 2>/dev/null \
            | xargs -0 -r ls -S 2>/dev/null | head -n1 || true)
  fi

  # --- folder name = HTML basename minus .html (or zip name as fallback) ---
  if [[ -n "$html" && -f "$html" ]]; then
    newname=$(basename "$html")
    newname="${newname%.*}"
  else
    newname="${f%.zip}"
  fi

  # --- sanitise for macOS ---
  newname="${newname//\//-}"
  newname="${newname//:/-}"

  # --- collision handling ---
  final="$newname"
  n=2
  while [[ -e "$final" ]]; do
    final="${newname} (${n})"
    n=$((n+1))
  done

  # --- rename temp dir -> final ---
  if mv "$tmpdir" "$final"; then
    echo "   -> $final"
  else
    echo "!! RENAME FAILED -> $final" >&2
  fi
done

# clean up any leftover empty temp dirs
find "$DEST" -maxdepth 1 -type d -name '.__extracting__' -empty -delete 2>/dev/null || true

echo "Done. Contents in: $DEST"

cd ~/Downloads

# sanity check: what will be affected
ls -d pczone/*/flipbook_*

# flatten
for d in pczone/*/flipbook_*; do
  [[ -d "$d" ]] || continue
  parent="$(dirname "$d")"
  echo "Moving: $d -> $parent"
  shopt -s dotglob
  mv -n -- "$d"/* "$parent"/
  shopt -u dotglob
  rmdir -- "$d"
done


EOF

# 2. Make it executable
chmod +x ~/pczone.sh

# 3. Run it
~/pczone.sh
