#!/usr/bin/env python3
"""Fix config names in generate_project.py (use standard Debug/Release), then delete me."""
p = 'generate_project.py'
t = open(p).read()

replacements = [
    ('def xcconfig(name, settings):', 'def xcconfig(key, name, settings):'),
    ("{uid('cfg:' + name)}", "{uid('cfg:' + key)}"),
    ('xcconfig("project-Debug", {"ALWAYS_SEARCH_USER_PATHS"', 'xcconfig("project-Debug", "Debug", {"ALWAYS_SEARCH_USER_PATHS"'),
    ('xcconfig("project-Release", {"ALWAYS_SEARCH_USER_PATHS"', 'xcconfig("project-Release", "Release", {"ALWAYS_SEARCH_USER_PATHS"'),
    ('xcconfig("target-Debug", dbg)', 'xcconfig("target-Debug", "Debug", dbg)'),
    ('xcconfig("target-Release", dict(common_target))', 'xcconfig("target-Release", "Release", dict(common_target))'),
    ('xcconfig("testtarget-Debug", test_dbg)', 'xcconfig("testtarget-Debug", "Debug", test_dbg)'),
    ('xcconfig("testtarget-Release", dict(common_test))', 'xcconfig("testtarget-Release", "Release", dict(common_test))'),
]
for old, new in replacements:
    n = t.count(old)
    assert n == 1, f"expected 1 of {old!r}, found {n}"
    t = t.replace(old, new)
open(p, 'w').write(t)
print(f"fixed {len(replacements)} lines")
