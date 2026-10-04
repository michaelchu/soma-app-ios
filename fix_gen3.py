#!/usr/bin/env python3
"""Add TEST_HOST/BUNDLE_LOADER to test target in generate_project.py, then delete me."""
p = 'generate_project.py'
t = open(p).read()
old = 'common_test = {\n    "CODE_SIGN_STYLE": "Automatic",'
new = 'common_test = {\n    "BUNDLE_LOADER": \'"$(TEST_HOST)"\',\n    "CODE_SIGN_STYLE": "Automatic",'
n = t.count(old)
assert n == 1, f"expected 1 BUNDLE_LOADER spot, found {n}"
t = t.replace(old, new)
old2 = '"TARGETED_DEVICE_FAMILY": \'"1"\',\n}'
# Only the common_test block ends with } followed by test_dbg assignment
old2_full = old2 + '\ntest_dbg = dict(common_test)'
new2_full = '"TARGETED_DEVICE_FAMILY": \'"1"\',\n    "TEST_HOST": \'"$(BUILT_PRODUCTS_DIR)/Soma.app/Soma"\',\n}\ntest_dbg = dict(common_test)'
n2 = t.count(old2_full)
assert n2 == 1, f"expected 1 TEST_HOST spot, found {n2}"
t = t.replace(old2_full, new2_full)
open(p, 'w').write(t)
print("added TEST_HOST/BUNDLE_LOADER")
