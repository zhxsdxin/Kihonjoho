#!/usr/bin/env python3
"""
批量生成 AI 解析并写入 JSON。
用法:
  python3 generate_ai_explain.py fe_siken_viewer_2020.json --key sk-xxx       # 全部
  python3 generate_ai_explain.py fe_siken_viewer_2019.json --key sk-xxx --q 5  # 单题测试
  python3 generate_ai_explain.py fe_siken_viewer_2020.json --key sk-xxx --dry  # 仅预览
"""
import json, os, re, sys, time, argparse

API_URL = "https://api.deepseek.com/chat/completions"
MODEL = "deepseek-chat"

def strip_html(s):
    return re.sub(r'<[^>]*>', '', s or '').strip()

def build_prompt(q):
    p = '你是一位日本基本情報技術者考试的中文辅导老师。请用中文对以下题目进行详细解析，包括：\n'
    p += '1. 题目中文转述和考点分析\n'
    p += '2. 每个选项逐一分析（不直接说对错）\n'
    p += '3. 解题思路和涉及的知识点\n'
    p += '请使用 \\(...\\) 包裹行内公式，\\[...\\] 包裹独立公式。\n\n'
    p += '【题目】\n' + strip_html(q.get('mondai', '')) + '\n\n【选项】\n'
    for s in q.get('selects', []):
        p += s.get('label', '') + ': ' + strip_html(s.get('text', '')) + '\n'
    p += '\n【解説】\n' + strip_html(q.get('kaisetsu', '')) + '\n'
    return p

def call_api(api_key, prompt):
    import urllib.request, urllib.error
    body = json.dumps({
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.7,
        "max_tokens": 4096
    }).encode('utf-8')
    req = urllib.request.Request(API_URL, data=body, headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}"
    })
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode())
            return data['choices'][0]['message']['content']
    except urllib.error.HTTPError as e:
        body = e.read().decode()[:300]
        raise RuntimeError(f"HTTP {e.code}: {body}")
    except Exception as e:
        raise RuntimeError(str(e))

def main():
    parser = argparse.ArgumentParser(description="Batch AI explanation generator")
    parser.add_argument("json_file", help="Path to the JSON file")
    parser.add_argument("--key", required=True, help="DeepSeek API key")
    parser.add_argument("--q", type=int, default=0, help="Process only this question number")
    parser.add_argument("--delay", type=float, default=1.0, help="Delay between API calls (seconds)")
    parser.add_argument("--dry", action="store_true", help="Dry run: show prompt without calling API")
    parser.add_argument("--force", action="store_true", help="Re-generate even if ai_explain exists")
    args = parser.parse_args()

    with open(args.json_file, 'r', encoding='utf-8') as f:
        data = json.load(f)

    questions = data.get('questions', {})
    nums = [str(args.q)] if args.q else sorted(questions.keys(), key=int)
    total = len(nums)
    updated = 0

    for i, num in enumerate(nums):
        q = questions.get(num)
        if not q:
            continue

        existing = q.get('ai_explain', '')
        if len(existing) > 10 and not args.force:
            print(f"[{i+1}/{total}] 问{num}  跳过(已有解析)")
            continue

        prompt = build_prompt(q)

        if args.dry:
            print(f"\n{'='*60}")
            print(f"[{i+1}/{total}] 问{num}  DRY RUN - 提示词:")
            print(prompt[:500])
            continue

        try:
            print(f"[{i+1}/{total}] 问{num}  生成中...", end='', flush=True)
            text = call_api(args.key, prompt)
            q['ai_explain'] = text
            updated += 1
            print(f" ✓ ({len(text)}字)")
            time.sleep(args.delay)
        except RuntimeError as e:
            print(f" ✗ {e}")
            time.sleep(args.delay * 2)

    if updated > 0 and not args.dry:
        with open(args.json_file, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print(f"\n已更新 {updated} 题的 ai_explain → {args.json_file}")
        print("下一步: git add . && git commit -m 'add ai_explain' && git push")
    elif updated == 0 and not args.dry:
        print("\n所有题目已包含解析，无需更新。")

if __name__ == '__main__':
    main()
