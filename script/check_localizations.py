#!/usr/bin/env python3
"""Validate both translations and their format arguments without macOS dependencies."""
import collections
import json
import pathlib
import re

root = pathlib.Path(__file__).resolve().parent.parent
catalog = json.loads((root / 'TableViewer/Resources/Localizable.xcstrings').read_text())
# Positional arguments may be reordered by translators; their type must remain intact.
pattern = re.compile(r'%(?:(\d+)\$)?(?:[-+ #0]*)(?:\d+)?(?:\.\d+)?(lld|llu|ld|lu|d|u|f|g|@)')
def arguments(text):
    matches = pattern.findall(text.replace('%%', ''))
    return collections.Counter((int(position) if position else index, kind)
                               for index, (position, kind) in enumerate(matches, 1))

for key, entry in catalog['strings'].items():
    values = []
    for language in ('en', 'zh-Hans'):
        unit = entry['localizations'][language]['stringUnit']
        assert unit['state'] == 'translated' and unit['value'], (key, language)
        values.append(unit['value'])
    assert arguments(values[0]) == arguments(values[1]), key
    assert not re.search(r'[\u4e00-\u9fff]', values[0]), ('Untranslated English', key)
print(f"PASS: {len(catalog['strings'])} entries, English + Simplified Chinese, format arguments match")
