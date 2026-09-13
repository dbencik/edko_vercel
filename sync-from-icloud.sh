#!/bin/bash
# sync-from-icloud.sh
# Copies HTML files from iCloud shared folder to this repo, rebuilds index.html cards, commits & pushes.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
ICLOUD_DIR="/Users/dodo/Library/Mobile Documents/com~apple~CloudDocs/!Family/VERCEL EDKO 8"

# Ensure iCloud files are downloaded (not just stubs)
find "$ICLOUD_DIR" -name "*.html" -exec brctl download {} \; 2>/dev/null || true
sleep 2

cd "$REPO_DIR"

CHANGED=0

for src in "$ICLOUD_DIR"/*.html; do
  [ -f "$src" ] || continue
  fname="$(basename "$src")"

  # Normalize filename: lowercase, spaces to hyphens, remove special chars
  normalized="$(echo "$fname" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[—–]/-/g; s/[(),"'"'"']//g; s/--*/-/g; s/^-//; s/-$//' | sed 's/-\.html/.html/')"

  # Copy if new or changed
  if [ ! -f "$REPO_DIR/$normalized" ] || ! diff -q "$src" "$REPO_DIR/$normalized" > /dev/null 2>&1; then
    cp "$src" "$REPO_DIR/$normalized"
    echo "Copied: $fname -> $normalized"
    CHANGED=1
  fi
done

if [ "$CHANGED" -eq 0 ]; then
  echo "No changes detected."
  exit 0
fi

# --- Rebuild index.html card section ---
# Collect all HTML files except index.html, sorted newest first
CARD_FILES=()
while IFS= read -r f; do
  b="$(basename "$f")"
  [ "$b" = "index.html" ] && continue
  CARD_FILES+=("$b")
done < <(ls -t "$REPO_DIR"/*.html 2>/dev/null)

# Build cards HTML into a temp file
CARDS_TMP="$(mktemp)"

for file in "${CARD_FILES[@]}"; do
  # Extract <title> from the HTML file
  title="$(sed -n 's/.*<title>\([^<]*\)<\/title>.*/\1/p' "$REPO_DIR/$file" 2>/dev/null | head -1)"
  [ -z "$title" ] && title="$file"

  # Determine icon and class based on filename keywords
  lower="$(echo "$file $title" | tr '[:upper:]' '[:lower:]')"

  if echo "$lower" | grep -qiE 'flashcard|kartic'; then
    icon='🃏'; icon_class='flash'; desc='Precvic si pojmy pomocou karticiek'
  elif echo "$lower" | grep -qiE 'exam|test|quiz|kviz'; then
    icon='📝'; icon_class='exam'; desc='Otestuj si svoje vedomosti'
  elif echo "$lower" | grep -qiE 'worksheet|pracovn|interactive|drill'; then
    icon='✍️'; icon_class='worksheet'; desc='Interaktivny pracovny list'
  elif echo "$lower" | grep -qiE 'volb|election|obcian'; then
    icon='🗳️'; icon_class='history'; desc='Obcianska nauka'
  elif echo "$lower" | grep -qiE 'histor|dejep|revolution|enlighten|osvietens'; then
    icon='🏛️'; icon_class='history'; desc='Dejepis'
  elif echo "$lower" | grep -qiE 'video'; then
    icon='▶️'; icon_class='video'; desc='Video na pozretie'
  elif echo "$lower" | grep -qiE 'kniha|citanie|reading|book'; then
    icon='📖'; icon_class='exam'; desc='Citanie a porozumenie textu'
  else
    icon='📚'; icon_class='exam'; desc='Ucebny material'
  fi

  cat >> "$CARDS_TMP" <<CARD_END

  <a class="card" href="$file">
    <div class="card-icon $icon_class">$icon</div>
    <div class="card-body">
      <h2>$title</h2>
      <p>$desc</p>
    </div>
    <span class="arrow">→</span>
  </a>
CARD_END
done

# Replace the cards section in index.html
# Strategy: use python for reliable multi-line replacement
python3 - "$REPO_DIR/index.html" "$CARDS_TMP" <<'PYEOF'
import sys, re

index_path = sys.argv[1]
cards_path = sys.argv[2]

with open(index_path, 'r') as f:
    html = f.read()

with open(cards_path, 'r') as f:
    cards = f.read()

# Replace everything between <div class="cards"> and its closing </div>
pattern = r'(<div class="cards">).*?(</div>\s*\n\s*<div class="footer">)'
replacement = r'\1\n' + cards.replace('\\', '\\\\') + r'\n\2'
new_html = re.sub(pattern, replacement, html, flags=re.DOTALL)

with open(index_path, 'w') as f:
    f.write(new_html)

print(f"Rebuilt index.html with {cards.count('<a class=\"card\"')} cards.")
PYEOF

rm -f "$CARDS_TMP"

# Git commit and push
cd "$REPO_DIR"
git add -A
if git diff --cached --quiet; then
  echo "No git changes to commit."
  exit 0
fi

TIMESTAMP="$(date '+%Y-%m-%d %H:%M')"
git commit -m "Auto-sync from iCloud ($TIMESTAMP)"
git push origin main

echo "Pushed to GitHub successfully."
