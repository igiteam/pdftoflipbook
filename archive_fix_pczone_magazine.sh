#!/usr/bin/env bash
# fix_flipbooks.sh
# usage: ./fix_flipbooks.sh [pczone_dir]
set -euo pipefail

PCZONE="${1:-pczone}"
[[ -d "$PCZONE" ]] || { echo "Error: '$PCZONE' not found" >&2; exit 1; }

BACKUP_DIR="$PCZONE/html_before_changes"
mkdir -p "$BACKUP_DIR"

# --- canonical links taken from A (the update) ---
JQUERY_URL="https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/jquery-1.12.4.min.js"
TURNJS_URL="https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/magazine_turn.js"
RIBBON_URL="https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/ribbon.png"
RIBBON2_URL="https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/ribbon2.png"

# Collect HTML files (Bash 3.2-safe — no mapfile)
HTMLS=()
while IFS= read -r line; do
  HTMLS+=("$line")
done < <(find "$PCZONE" -mindepth 2 -maxdepth 2 -type f -name '*__flipbook.html' | sort)

if [[ ${#HTMLS[@]} -eq 0 ]]; then
  echo "No *__flipbook.html files found under $PCZONE/<title>__flipbook/" >&2
  exit 1
fi

echo "Found ${#HTMLS[@]} flipbook HTML file(s)."
echo

for f in "${HTMLS[@]}"; do
  base="$(basename "$f")"                 # PC_Zone_Issue_1__April_1993__flipbook.html
  backup="$BACKUP_DIR/$base"

  # 1) backup original (skip if already backed up — keep the very first copy)
  if [[ -f "$backup" ]]; then
    echo "  [backup exists] $backup"
  else
    cp -p "$f" "$backup"
    echo "  [backed up]     $backup"
  fi

  # 2) rewrite the links in-place
  tmp="$(mktemp)"
  sed \
    -e "s#https://code\.jquery\.com/jquery-1\.7\.1\.min\.js#${JQUERY_URL}#g" \
    -e "s#https://cdn\.gitgpt\.chat/rtx/magazine_turn\.js#${TURNJS_URL}#g" \
    -e "s#https://cdn\.gitgpt\.chat/rtx/images/ribbon\.png#${RIBBON_URL}#g" \
    -e "s#https://cdn\.gitgpt\.chat/rtx/images/ribbon2\.png#${RIBBON2_URL}#g" \
    "$f" > "$tmp"

  mv "$tmp" "$f"
  echo "  [updated]       $f"
done

echo
echo "Done. Backups in: $BACKUP_DIR"
echo
echo "Backed-up files:"
ls -1 "$BACKUP_DIR"

cd ~/Downloads
diff pczone/html_before_changes/PC_Zone_Issue_1__April_1993__flipbook.html \
     pczone/PC_Zone_Issue_1__April_1993__flipbook/PC_Zone_Issue_1__April_1993__flipbook.html

for u in \
  "https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/jquery-1.12.4.min.js" \
  "https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/magazine_turn.js" \
  "https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/ribbon.png" \
  "https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/ribbon2.png"; do
  printf '%s -> ' "$u"
  curl -s -o /dev/null -w '%{http_code}\n' -L "$u"
done


#!/usr/bin/env bash
# zip_pczone.sh
# usage: ./zip_pczone.sh [pczone_dir] [out_dir]
set -euo pipefail

PCZONE="${1:-pczone}"
OUTDIR="${2:-pczone_archive}"

[[ -d "$PCZONE" ]] || { echo "Error: '$PCZONE' not found" >&2; exit 1; }
mkdir -p "$OUTDIR"

count=0
for d in "$PCZONE"/*/; do
  [[ -d "$d" ]] || continue
  name="$(basename "$d")"

  # skip the backup dir — it's not a flipbook folder
  [[ "$name" == "html_before_changes" ]] && continue

  # only zip folders that actually look like flipbooks
  [[ "$name" == *__flipbook ]] || continue

  zip_path="$OUTDIR/$name.zip"

  if [[ -f "$zip_path" ]]; then
    echo "  [skip, exists] $zip_path"
    continue
  fi

  echo "  [zipping] $d -> $zip_path"
  # -r recurse, -q quiet, -X strip extra file attrs (cleaner on archive.org)
  ( cd "$PCZONE" && zip -rqX "$(cd "$OLDPWD" && pwd)/$zip_path" "$name" )
  count=$((count + 1))
done

echo
echo "Done. $count new zip(s) in $OUTDIR"
echo
ls -lh "$OUTDIR"/*.zip 2>/dev/null | awk '{print $5, $9}'
