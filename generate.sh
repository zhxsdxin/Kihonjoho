#!/bin/bash
set -e

# Default values
YEAR="02_menjo"
COUNT=80
OUTPUT_DIR="pages"
JSON_NAME=""
DELAY_MS=200
PUSH=false
CLEAN=false

usage() {
    echo "Usage: $0 [-Year year] [-Count n] [-OutputDir dir] [-JsonName name] [-DelayMs ms] [-Push] [-Clean]"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -Year)        YEAR="$2"; shift 2 ;;
        -Count)       COUNT="$2"; shift 2 ;;
        -OutputDir)   OUTPUT_DIR="$2"; shift 2 ;;
        -JsonName)    JSON_NAME="$2"; shift 2 ;;
        -DelayMs)     DELAY_MS="$2"; shift 2 ;;
        -Push)        PUSH=true; shift ;;
        -Clean)       CLEAN=true; shift ;;
        -h|--help)    usage ;;
        *)            echo "Unknown option: $1"; usage ;;
    esac
done

BASE_URL="https://www.fe-siken.com/kakomon/${YEAR}/q"

if [[ -z "$JSON_NAME" ]]; then
    JSON_NAME="fe_siken_viewer_${YEAR//_/}"
fi
JSON_NAME="${JSON_NAME%.json}.json"
SUFFIX="${JSON_NAME%.json}"
if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="$SUFFIX"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PAGES_PATH="${SCRIPT_DIR}/${OUTPUT_DIR}"
JSON_PATH="${SCRIPT_DIR}/${JSON_NAME}"

# Color helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
GRAY='\033[1;30m'
NC='\033[0m'

# ── 1. Download pages ──────────────────────────────────────────────
echo -e "${CYAN}=== 下载 ${YEAR} q1~q${COUNT} ===${NC}"
mkdir -p "$PAGES_PATH"

for ((i=1; i<=COUNT; i++)); do
    URL="${BASE_URL}${i}.html"
    FILE="${PAGES_PATH}/q${i}.html"
    if [[ -f "$FILE" ]]; then
        echo -e "  [${i}/${COUNT}] ${GRAY}跳过(已存在)${NC}"
    else
        HTTP_CODE=$(curl -sL -o "$FILE" -w "%{http_code}" --connect-timeout 10 "$URL")
        if [[ "$HTTP_CODE" == "200" ]] || [[ "$HTTP_CODE" == "302" ]]; then
            echo -e "  [${i}/${COUNT}] ${GREEN}✓${NC}"
        else
            echo -e "  [${i}/${COUNT}] ${RED}✗ HTTP ${HTTP_CODE}${NC}"
            rm -f "$FILE"
        fi
        if [[ "$DELAY_MS" -gt 0 && "$i" -lt "$COUNT" ]]; then
            sleep "$(echo "scale=3; $DELAY_MS / 1000" | bc)"
        fi
    fi
done

# ── 2. Parse pages & generate JSON ─────────────────────────────────
echo -e "\n${CYAN}=== 生成 JSON ===${NC}"

python3 - "$PAGES_PATH" "$COUNT" "$YEAR" "$JSON_PATH" "$JSON_NAME" << 'PYEOF'
import sys, os, json, re, html as html_mod

pages_path = sys.argv[1]
count = int(sys.argv[2])
year = sys.argv[3]
json_path = sys.argv[4]
json_name = sys.argv[5]

chars = ['ア','イ','ウ','エ','オ','カ','キ','ク','ケ','コ']
base = f"https://www.fe-siken.com/kakomon/{year}/"

def fix_url(text):
    def repl(m):
        attr = m.group(1)
        url = m.group(2)
        if url.startswith('/'):
            return f'{attr}="https://www.fe-siken.com{url}"'
        elif not url.startswith('http'):
            return f'{attr}="{base}{url}"'
        return m.group(0)
    return re.sub(r'(src|href)="(?!https?://)([^"]+)"', repl, text)

questions = {}
for i in range(1, count + 1):
    fpath = os.path.join(pages_path, f"q{i}.html")
    if not os.path.isfile(fpath):
        print(f"  [{i}/{count}] ✗ 文件不存在")
        continue
    with open(fpath, 'r', encoding='utf-8') as f:
        html = f.read()

    # Extract #mondai content (until ansbg)
    mondai = ""
    m = re.search(r'<div\s+id="mondai"[^>]*>', html)
    if m:
        ms = m.end()
        me = html.find('<div class="ansbg"', ms)
        if me > ms:
            mondai_raw = html[ms:me].strip()
            mondai_raw = re.sub(r'</div>\s*$', '', mondai_raw)
            mondai = fix_url(mondai_raw)

    # Extract options
    selects = []
    sm = re.search(r'<ul\s+class="selectList[^"]*"[^>]*>(.*?)</ul>', html, re.DOTALL)
    if sm:
        list_html = sm.group(1)
        li_matches = re.findall(r'<li>(.*?)</li>', list_html, re.DOTALL)
        for li_content in li_matches:
            btns = re.findall(r'<button[^>]*>(.*?)</button>', li_content, re.DOTALL)
            if len(btns) > 1:
                pre = re.sub(r'(<button[^>]*>.*?</button>\s*)+', '', li_content, flags=re.DOTALL)
                pre = fix_url(pre.strip())
                for btn_text in btns:
                    # Check if this specific button has id="t"
                    btn_pat = re.compile(re.escape(btn_text.strip()))
                    btn_m = re.search(r'<button[^>]*id="t"[^>]*>' + re.escape(btn_text.strip()) + r'</button>', li_content)
                    is_correct = btn_m is not None
                    selects.append({"label": btn_text.strip(), "text": pre, "isCorrect": is_correct})
            else:
                is_correct = 'id="t"' in li_content
                text = re.sub(r'<button[^>]*>.*?</button>', '', li_content, flags=re.DOTALL)
                text = fix_url(text.strip())
                idx = len(selects)
                label = chars[idx] if idx < len(chars) else ""
                selects.append({"label": label, "text": text, "isCorrect": is_correct})

    # Extract answer
    am = re.search(r'<span\s+id="answerChar"[^>]*>(.*?)</span>', html)
    answer = am.group(1).strip() if am else ""

    # Extract #kaisetsu content (until social-btn)
    kaisetsu = ""
    km = re.search(r'<div[^>]*\sid="kaisetsu"[^>]*>', html)
    if km:
        ks = km.end()
        ke = html.find('social-btn', ks)
        if ke > ks:
            ke = html.rfind('</div>', ks, ke)
            kaisetsu = fix_url(html[ks:ke].strip())

    # Extract category
    info = ""
    cat_m = re.search(r'<h3>分類\s*:\s*</h3>\s*<div>(.*?)</div>', html, re.DOTALL)
    if cat_m:
        info = fix_url(f"<strong>分類:</strong> {cat_m.group(1).strip()}")

    questions[str(i)] = {
        "mondai": mondai,
        "selects": selects,
        "answer": answer,
        "kaisetsu": kaisetsu,
        "info": info
    }
    print(f"  [{i}/{count}] ✓", end="")

json_data = {
    "version": 3,
    "type": "full",
    "marks": {},
    "questions": questions
}
print(f"\n  已解析 {len(questions)} 题")
print(f"  输出: {json_name}")

with open(json_path, 'w', encoding='utf-8') as f:
    json.dump(json_data, f, ensure_ascii=False, indent=2)
print(f"  已写入 {json_path}")
PYEOF

# ── 3. Clean pages ─────────────────────────────────────────────────
if $CLEAN; then
    echo -e "\n${CYAN}=== 删除 ${OUTPUT_DIR} ===${NC}"
    rm -rf "$PAGES_PATH"
    echo -e "${GREEN}  已删除${NC}"
fi

# ── 4. Git push ────────────────────────────────────────────────────
if $PUSH; then
    STATUS=$(git -C "$SCRIPT_DIR" status --porcelain 2>/dev/null || true)
    if [[ -n "$STATUS" ]]; then
        echo -e "\n${CYAN}=== Git 推送 ===${NC}"
        git -C "$SCRIPT_DIR" add -A
        git -C "$SCRIPT_DIR" commit -m "generate ${JSON_NAME} for ${YEAR}"
        git -C "$SCRIPT_DIR" push
        echo -e "${GREEN}  推送完成${NC}"
    else
        echo -e "\n${GRAY}Git: 无变更${NC}"
    fi
fi

echo -e "\n${CYAN}=== 完成 ===${NC}"
