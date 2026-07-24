#!/usr/bin/env python3
"""Validate locale JSONs against the English source: key parity + HTML tag integrity."""
import json, re, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
en = json.load(open(os.path.join(HERE, 'en.json')))
en_keys = set(en)

# keys whose English value contains markup we must preserve
html_keys = {k: v for k, v in en.items() if '<' in v}
tag_re = re.compile(r'<[^>]+>')

def tags(s):
    # normalized multiset of tags (opening tag name + closing), order-insensitive.
    # Collapse whitespace *inside* each tag so cosmetic differences (en.json keeps
    # the source HTML's line-wrapped attributes; translations single-line the same
    # tag) don't read as a structural mismatch.
    return sorted(re.sub(r'\s+', ' ', t) for t in tag_re.findall(s))

locales = ['ar','de','es','fr','hi','id','it','ja','ko','nl','pl','pt','ru','th','tr','uk','vi','zh','zh-Hant']
ok = True
for loc in locales:
    path = os.path.join(HERE, loc + '.json')
    if not os.path.exists(path):
        print(f'[MISSING] {loc}.json'); ok = False; continue
    try:
        d = json.load(open(path))
    except Exception as e:
        print(f'[BADJSON] {loc}: {e}'); ok = False; continue
    problems = []
    miss = en_keys - set(d)
    extra = set(d) - en_keys
    if miss: problems.append(f'missing {len(miss)}: {sorted(miss)[:5]}')
    if extra: problems.append(f'extra {len(extra)}: {sorted(extra)[:5]}')
    for k, ev in html_keys.items():
        if k in d and tags(d[k]) != tags(ev):
            problems.append(f'tag-mismatch [{k}]: {tags(d[k])} != {tags(ev)}')
    # untranslated: identical to English (allow short brand-only strings)
    same = [k for k in d if k in en and d[k] == en[k] and len(en[k]) > 12 and '<' not in en[k]]
    if problems:
        ok = False
        print(f'[FAIL] {loc}: ' + ' | '.join(problems))
    else:
        note = f' (note: {len(same)} values identical to EN)' if same else ''
        print(f'[ok]   {loc}: {len(d)} keys, tags intact{note}')

print('\nRESULT:', 'ALL GOOD' if ok else 'PROBLEMS FOUND')
sys.exit(0 if ok else 1)
