#!/bin/bash
# sync-from-icloud.sh
# 1. Copies HTML files from iCloud shared folder to this repo
# 2. Injects edko-reporter.js into each worksheet
# 3. Rebuilds index.html card section
# 4. Downloads uploads from Vercel Blob to iCloud
# 5. Commits & pushes

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
ICLOUD_DIR="/Users/dodo/Library/Mobile Documents/com~apple~CloudDocs/!Family/VERCEL EDKO 8"
ICLOUD_UPLOADS="$ICLOUD_DIR/UPLOADS"

# Ensure iCloud files are downloaded (not just stubs)
find "$ICLOUD_DIR" -name "*.html" -exec brctl download {} \; 2>/dev/null || true
sleep 2

cd "$REPO_DIR"

CHANGED=0

# --- Step 1: Copy HTML files from iCloud ---
for src in "$ICLOUD_DIR"/*.html; do
  [ -f "$src" ] || continue
  fname="$(basename "$src")"

  # Normalize filename: lowercase, spaces to hyphens, remove special chars
  normalized="$(echo "$fname" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[—–]/-/g; s/[(),"'"'"']//g; s/--*/-/g; s/^-//; s/-$//' | sed 's/-\.html/.html/')"

  # Copy if new or changed
  if [ ! -f "$REPO_DIR/$normalized" ] || ! diff -q "$src" "$REPO_DIR/$normalized" > /dev/null 2>&1; then
    cp -p "$src" "$REPO_DIR/$normalized"
    echo "Copied: $fname -> $normalized"
    CHANGED=1
  fi
done

# --- Step 2: Inject edko-reporter.js into worksheets ---
for f in "$REPO_DIR"/*.html; do
  base="$(basename "$f")"
  # Skip non-worksheet files
  case "$base" in
    index.html|rodic.html|upload.html) continue ;;
  esac

  # Check if reporter is already injected
  if ! grep -q 'edko-reporter.js' "$f" 2>/dev/null; then
    # Inject before </body>
    sed -i '' 's|</body>|<script src="edko-reporter.js"></script>\n</body>|' "$f"
    echo "Injected reporter into: $base"
    CHANGED=1
  fi
done

if [ "$CHANGED" -eq 0 ]; then
  echo "No changes detected."
else
  # --- Step 3: Rebuild index.html card section ---
  # Collect worksheet HTML files (exclude utility pages), sorted newest first
  CARD_FILES=()
  while IFS= read -r f; do
    b="$(basename "$f")"
    case "$b" in
      index.html|rodic.html|upload.html) continue ;;
    esac
    CARD_FILES+=("$b")
  done < <(ls -t "$REPO_DIR"/*.html 2>/dev/null)

  # Build cards HTML into a temp file
  CARDS_TMP="$(mktemp)"

  # Number cards: oldest = #1 (reverse the newest-first list)
  TOTAL=${#CARD_FILES[@]}

  for file in "${CARD_FILES[@]}"; do
    # Extract <title> from the HTML file
    title="$(sed -n 's/.*<title>\([^<]*\)<\/title>.*/\1/p' "$REPO_DIR/$file" 2>/dev/null | head -1)"
    [ -z "$title" ] && title="$file"

    # Determine description based on filename keywords
    lower="$(echo "$file $title" | tr '[:upper:]' '[:lower:]')"

    if echo "$lower" | grep -qiE 'flashcard|kartic'; then
      desc='Karty'
    elif echo "$lower" | grep -qiE 'exam|test|quiz|kviz'; then
      desc='Kviz'
    elif echo "$lower" | grep -qiE 'worksheet|pracovn|interactive|drill'; then
      desc='Worksheet'
    elif echo "$lower" | grep -qiE 'kniha|citanie|reading|book'; then
      desc='Citanie'
    else
      desc='Ucenie'
    fi

    cat >> "$CARDS_TMP" <<CARD_END

  <a class="card" href="$file">
    <div class="card-num">$TOTAL</div>
    <div class="card-body">
      <h2>$title</h2>
      <p>$desc</p>
    </div>
  </a>
CARD_END
    TOTAL=$((TOTAL - 1))
  done


  # Replace the cards section in index.html using python
  python3 - "$REPO_DIR/index.html" "$CARDS_TMP" <<'PYEOF'
import sys, re

index_path = sys.argv[1]
cards_path = sys.argv[2]

with open(index_path, 'r') as f:
    html = f.read()

with open(cards_path, 'r') as f:
    cards = f.read()

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
  else
    TIMESTAMP="$(date '+%Y-%m-%d %H:%M')"
    git commit -m "Auto-sync from iCloud ($TIMESTAMP)"
    git push origin main
    echo "Pushed to GitHub successfully."
  fi
fi

# --- Step 4: Download uploads from Vercel to iCloud ---
mkdir -p "$ICLOUD_UPLOADS"

# List uploads via our API (no token needed)
UPLOADS_JSON="$(curl -s "https://edko.vercel.app/api/upload" 2>/dev/null || echo '[]')"

echo "$UPLOADS_JSON" | python3 -c "
import sys, json, os, urllib.request

data = json.load(sys.stdin)
uploads_dir = '$ICLOUD_UPLOADS'
downloaded = 0

# data is an array of blob objects
blobs = data if isinstance(data, list) else []
for blob in blobs:
    url = blob.get('url', '')
    name = blob.get('pathname', '').replace('uploads/', '', 1)
    if not name:
        continue
    dest = os.path.join(uploads_dir, name)
    if not os.path.exists(dest):
        try:
            urllib.request.urlretrieve(url, dest)
            print(f'Downloaded: {name}')
            downloaded += 1
        except Exception as e:
            print(f'Failed to download {name}: {e}')

if downloaded == 0:
    print('No new uploads to download.')
else:
    print(f'Downloaded {downloaded} new file(s) to iCloud.')
" 2>&1 || echo "Upload download skipped."
