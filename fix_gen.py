#!/usr/bin/env python3
"""Fix doubled braces in generate_project.py (transcription error), then delete me."""
p = 'generate_project.py'
t = open(p).read()
old = 'A("\\t\\t); runOnlyForDeploymentPostprocessing = 0; }};")'
new = 'A("\\t\\t); runOnlyForDeploymentPostprocessing = 0; };")'
n = t.count(old)
assert n == 3, f"expected 3 broken lines, found {n}"
open(p, 'w').write(t.replace(old, new))
print("fixed 3 lines")
