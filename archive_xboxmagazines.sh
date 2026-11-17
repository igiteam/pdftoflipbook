# 1. Create the file with a heredoc (paste this whole block at once)
cat > ~/oxm.sh <<'EOF'
#!/bin/bash
set -euo pipefail

BASE="https://archive.org/download/official-xbox-magazine-complete-collection"
DEST="$HOME/Downloads/oxm"
mkdir -p "$DEST"
cd "$DEST"

files=(
  "Official_Xbox_Magazine%2C_Issue_0%2C_Special_E3_Collectors_Issue.zip"
  "Official_Xbox_Magazine%2C_Issue_1.zip"
  "Official_Xbox_Magazine%2C_Issue_2.zip"
  "Official_Xbox_Magazine%2C_Issue_3.zip"
  "Official_Xbox_Magazine%2C_Issue_4.zip"
  "Official_Xbox_Magazine%2C_Issue_5.zip"
  "Official_Xbox_Magazine%2C_Issue_6.zip"
  "Official_Xbox_Magazine%2C_Issue_7.zip"
  "Official_Xbox_Magazine%2C_Issue_8.zip"
  "Official_Xbox_Magazine%2C_Issue_9.zip"
  "Official_Xbox_Magazine%2C_Issue_10.zip"
  "Official_Xbox_Magazine%2C_Issue_11.zip"
  "Official_Xbox_Magazine%2C_Issue_12.zip"
  "Official_Xbox_Magazine%2C_Issue_13.zip"
  "Official_Xbox_Magazine%2C_Issue_14.zip"
  "Official_Xbox_Magazine%2C_Issue_15.zip"
  "Official_Xbox_Magazine%2C_Issue_16.zip"
  "Official_Xbox_Magazine%2C_Issue_17.zip"
  "Official_Xbox_Magazine%2C_Issue_18.zip"
  "Official_Xbox_Magazine%2C_Issue_19.zip"
  "Official_Xbox_Magazine%2C_Issue_20.zip"
  "Official_Xbox_Magazine%2C_Issue_22.zip"
  "Official_Xbox_Magazine%2C_Issue_23.zip"
  "Official_Xbox_Magazine%2C_Issue_24.zip"
  "Official_Xbox_Magazine%2C_Issue_25.zip"
  "Official_Xbox_Magazine%2C_Issue_26.zip"
  "Official_Xbox_Magazine%2C_Issue_27.zip"
  "Official_Xbox_Magazine%2C_Issue_28.zip"
  "Official_Xbox_Magazine%2C_Issue_29.zip"
  "Official_Xbox_Magazine%2C_Issue_30.zip"
  "Official_Xbox_Magazine%2C_Issue_31.zip"
  "Official_Xbox_Magazine%2C_Issue_32.zip"
  "Official_Xbox_Magazine%2C_Issue_33.zip"
  "Official_Xbox_Magazine%2C_Issue_34.zip"
  "Official_Xbox_Magazine%2C_Issue_35.zip"
  "Official_Xbox_Magazine%2C_Issue_36.zip"
  "Official_Xbox_Magazine%2C_Issue_37.zip"
  "Official_Xbox_Magazine%2C_Issue_38.zip"
  "Official_Xbox_Magazine%2C_Issue_39.zip"
  "Official_Xbox_Magazine%2C_Issue_40.zip"
  "Official_Xbox_Magazine%2C_Issue_41.zip"
  "Official_Xbox_Magazine%2C_Issue_42.zip"
  "Official_Xbox_Magazine%2C_Issue_43.zip"
  "Official_Xbox_Magazine%2C_Issue_44.zip"
  "Official_Xbox_Magazine%2C_Issue_45.zip"
  "Official_Xbox_Magazine%2C_Issue_46.zip"
  "Official_Xbox_Magazine%2C_Issue_47.zip"
  "Official_Xbox_Magazine%2C_Issue_48.zip"
  "Official_Xbox_Magazine%2C_Issue_49.zip"
  "Official_Xbox_Magazine%2C_Issue_50.zip"
  "Official_Xbox_Magazine%2C_Issue_51.zip"
  "Official_Xbox_Magazine%2C_Issue_52.zip"
  "Official_Xbox_Magazine%2C_Issue_53.zip"
  "Official_Xbox_Magazine%2C_Issue_54.zip"
  "Official_Xbox_Magazine%2C_Issue_55.zip"
  "Official_Xbox_Magazine%2C_Issue_56.zip"
  "Official_Xbox_Magazine%2C_Issue_57.zip"
  "Official_Xbox_Magazine%2C_Issue_58.zip"
  "Official_Xbox_Magazine%2C_Issue_59.zip"
  "Official_Xbox_Magazine%2C_Issue_60.zip"
  "Official_Xbox_Magazine%2C_Issue_61.zip"
  "Official_Xbox_Magazine%2C_Issue_62.zip"
  "Official_Xbox_Magazine%2C_Issue_63.zip"
  "Official_Xbox_Magazine%2C_Issue_64.zip"
  "Official_Xbox_Magazine%2C_Issue_65.zip"
  "Official_Xbox_Magazine%2C_Issue_66.zip"
  "Official_Xbox_Magazine%2C_Issue_67.zip"
  "Official_Xbox_Magazine%2C_Issue_68.zip"
  "Official_Xbox_Magazine%2C_Issue_69.zip"
  "Official_Xbox_Magazine%2C_Issue_70.zip"
  "Official_Xbox_Magazine%2C_Issue_71.zip"
  "Official_Xbox_Magazine%2C_Issue_72.zip"
  "Official_Xbox_Magazine%2C_Issue_73.zip"
  "Official_Xbox_Magazine%2C_Issue_74.zip"
  "Official_Xbox_Magazine%2C_Issue_75.zip"
  "Official_Xbox_Magazine%2C_Issue_76.zip"
  "Official_Xbox_Magazine%2C_Issue_77.zip"
  "Official_Xbox_Magazine%2C_Issue_78.zip"
  "Official_Xbox_Magazine%2C_Issue_79.zip"
  "Official_Xbox_Magazine%2C_Issue_80.zip"
  "Official_Xbox_Magazine%2C_Issue_81.zip"
  "Official_Xbox_Magazine%2C_Issue_82.zip"
  "Official_Xbox_Magazine%2C_Issue_83.zip"
  "Official_Xbox_Magazine%2C_Issue_84.zip"
  "Official_Xbox_Magazine%2C_Issue_85.zip"
  "Official_Xbox_Magazine%2C_Issue_86.zip"
  "Official_Xbox_Magazine%2C_Issue_87.zip"
  "Official_Xbox_Magazine%2C_Issue_88.zip"
  "Official_Xbox_Magazine%2C_Issue_89.zip"
  "Official_Xbox_Magazine%2C_Issue_90.zip"
  "Official_Xbox_Magazine%2C_Issue_91.zip"
  "Official_Xbox_Magazine%2C_Issue_92.zip"
  "Official_Xbox_Magazine%2C_Issue_93.zip"
  "Official_Xbox_Magazine%2C_Issue_94.zip"
  "Official_Xbox_Magazine%2C_Issue_95.zip"
  "Official_Xbox_Magazine%2C_Issue_96.zip"
  "Official_Xbox_Magazine%2C_Issue_97.zip"
  "Official_Xbox_Magazine%2C_Issue_98.zip"
  "Official_Xbox_Magazine%2C_Issue_99.zip"
  "Official_Xbox_Magazine%2C_Issue_100.zip"
  "Official_Xbox_Magazine%2C_Issue_101.zip"
  "Official_Xbox_Magazine%2C_Issue_102.zip"
  "Official_Xbox_Magazine%2C_Issue_103.zip"
  "Official_Xbox_Magazine%2C_Issue_104.zip"
  "Official_Xbox_Magazine%2C_Issue_105.zip"
  "Official_Xbox_Magazine%2C_Issue_106.zip"
  "Official_Xbox_Magazine%2C_Issue_107.zip"
  "Official_Xbox_Magazine%2C_Issue_108.zip"
  "Official_Xbox_Magazine%2C_Issue_109.zip"
  "Official_Xbox_Magazine%2C_Issue_110.zip"
  "Official_Xbox_Magazine%2C_Issue_111.zip"
  "Official_Xbox_Magazine%2C_Issue_112.zip"
  "Official_Xbox_Magazine%2C_Issue_113.zip"
  "Official_Xbox_Magazine%2C_Issue_114.zip"
  "Official_Xbox_Magazine%2C_Issue_115.zip"
  "Official_Xbox_Magazine%2C_Issue_116.zip"
  "Official_Xbox_Magazine%2C_Issue_117.zip"
  "Official_Xbox_Magazine%2C_Issue_118.zip"
  "Official_Xbox_Magazine%2C_Issue_119.zip"
  "Official_Xbox_Magazine%2C_Issue_120.zip"
  "Official_Xbox_Magazine%2C_Issue_121.zip"
  "Official_Xbox_Magazine%2C_Issue_122.zip"
  "Official_Xbox_Magazine%2C_Issue_123.zip"
  "Official_Xbox_Magazine%2C_Issue_124.zip"
  "Official_Xbox_Magazine%2C_Issue_125.zip"
  "Official_Xbox_Magazine%2C_Issue_126.zip"
  "Official_Xbox_Magazine%2C_Issue_127.zip"
  "Official_Xbox_Magazine%2C_Issue_129.zip"
  "Official_Xbox_Magazine%2C_Issue_130.zip"
  "Official_Xbox_Magazine%2C_Issue_131.zip"
  "Official_Xbox_Magazine%2C_Issue_132.zip"
  "Official_Xbox_Magazine%2C_Issue_133.zip"
  "Official_Xbox_Magazine%2C_Special_Preview_Issue.zip"
  "manifest.json"
  "official-xbox-magazine-complete-collection_archive.torrent"
  "official-xbox-magazine-complete-collection_files.xml"
  "official-xbox-magazine-complete-collection_meta.sqlite"
  "official-xbox-magazine-complete-collection_meta.xml"
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
EOF

# 2. Make it executable
chmod +x ~/oxm.sh

# 3. Run it
~/oxm.sh
