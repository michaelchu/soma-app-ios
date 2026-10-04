#!/usr/bin/env python3
"""Generate Soma.xcodeproj/project.pbxproj by walking Soma/.

Deterministic 24-hex IDs derived from file paths, so regenerating is stable.

Group/file paths are relative to the parent group (Xcode convention):
the root group is path="Soma", subgroups use their basename, and file
references use their basename. The .xcassets dir is a single file reference
(folder.assetcatalog), not a group.
"""
import hashlib
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "Soma")
TEST_SRC = os.path.join(ROOT, "SomaTests")
PROJDIR = os.path.join(ROOT, "Soma.xcodeproj")


def uid(s: str) -> str:
    return hashlib.sha256(s.encode()).hexdigest()[:24].upper()


FILETYPE = {
    ".swift": "sourcecode.swift",
    ".ttf": "file",
    ".otf": "file",
    ".xcassets": "folder.assetcatalog",
    ".plist": "text.plist.xml",
    ".entitlements": "text.plist.xml",
}


def parent_dir(relpath: str) -> str:
    """Parent dir of a SRC-relative path, with SRC root normalized to '.'."""
    return os.path.dirname(relpath) or "."


# Collect files relative to SRC.
# - .swift -> sources, .ttf/.otf/.xcassets -> resources
# - the .xcassets dir itself is one file reference; its internal files
#   (Contents.json, .appiconset) are owned by the catalog.
entries = []  # (relpath, kind)
for dirpath, dirnames, filenames in os.walk(SRC):
    dirnames.sort()
    if dirpath.endswith(".xcassets"):
        # Asset catalogs are referenced as one unit (folder.assetcatalog);
        # their internal files (Contents.json) are owned by the catalog.
        entries.append((os.path.relpath(dirpath, SRC), "assetdir"))
        dirnames[:] = []
        continue
    if ".appiconset" in dirpath or ".xcassets" in dirpath:
        dirnames[:] = []
        continue
    for fn in sorted(filenames):
        if fn == ".DS_Store":
            continue
        rel = os.path.relpath(os.path.join(dirpath, fn), SRC)
        entries.append((rel, "file"))

sources = [p for p, k in entries if k == "file" and p.endswith(".swift")]
resources = [p for p, k in entries if k == "file" and (p.endswith(".ttf") or p.endswith(".otf"))]
resources += [p for p, k in entries if k == "assetdir"]
# Info.plist / entitlements are referenced but not in build phases.

# Test sources live under SomaTests/ (sibling of Soma/). They get their own
# group/target; ids are prefixed to avoid colliding with app paths.
test_entries = []  # relpath relative to TEST_SRC
if os.path.isdir(TEST_SRC):
    for dirpath, dirnames, filenames in os.walk(TEST_SRC):
        dirnames.sort()
        for fn in sorted(filenames):
            if fn == ".DS_Store" or not fn.endswith(".swift"):
                continue
            test_entries.append(os.path.relpath(os.path.join(dirpath, fn), TEST_SRC))

lines = []
A = lines.append


def ref_id(p):
    return uid("ref:" + p)


def build_id(p):
    return uid("build:" + p)


def test_ref_id(p):
    return uid("testref:" + p)


def test_build_id(p):
    return uid("testbuild:" + p)


A("// !$*UTF8*$!")
A("{")
A("\tarchiveVersion = 1;")
A("\tclasses = {")
A("\t};")
A("\tobjectVersion = 56;")
A("\tobjects = {")

# --- PBXBuildFile ---
for p in sources + resources:
    A(f"\t\t{build_id(p)} = {{isa = PBXBuildFile; fileRef = {ref_id(p)}; }};")
for p in test_entries:
    A(f"\t\t{test_build_id(p)} = {{isa = PBXBuildFile; fileRef = {test_ref_id(p)}; }};")

# --- PBXFileReference (path = basename, relative to parent group) ---
for p, k in entries:
    if k not in ("file", "assetdir"):
        continue
    ext = os.path.splitext(p)[1]
    ftype = FILETYPE.get(ext, "file")
    name = os.path.basename(p)
    A(f'\t\t{ref_id(p)} = {{isa = PBXFileReference; lastKnownFileType = {ftype}; name = "{name}"; path = "{name}"; sourceTree = "<group>"; }};')
APP_REF = uid("ref:app")
A(f"\t\t{APP_REF} = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Soma.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
# Test bundle product + test sources
TEST_BUNDLE_REF = uid("testref:bundle")
A(f"\t\t{TEST_BUNDLE_REF} = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = SomaTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
for p in test_entries:
    name = os.path.basename(p)
    A(f'\t\t{test_ref_id(p)} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = "{name}"; path = "{name}"; sourceTree = "<group>"; }};')

# --- PBXGroup (mirrors folders; path = basename relative to parent) ---
dirs = sorted({parent_dir(p) for p, k in entries if k in ("file", "assetdir")} | {"."})
dir_id = {d: uid("group:" + d) for d in dirs}
for d in dirs:
    children = []
    for p, k in entries:
        if k not in ("file", "assetdir"):
            continue
        if parent_dir(p) == d:
            children.append(ref_id(p))
    for sub in sorted({x for x in dirs if parent_dir(x) == d and x != d}):
        children.append(dir_id[sub])
    name = "Soma" if d == "." else os.path.basename(d)
    kids = ", ".join(children)
    A(f'\t\t{dir_id[d]} = {{isa = PBXGroup; children = ({kids}); name = "{name}"; path = "{name}"; sourceTree = "<group>"; }};')
MAIN_GROUP = uid("group:main")
TEST_GROUP = uid("group:test")
test_kids = ", ".join(test_ref_id(p) for p in test_entries)
A(f'\t\t{TEST_GROUP} = {{isa = PBXGroup; children = ({test_kids}); name = "SomaTests"; path = "SomaTests"; sourceTree = "<group>"; }};')
A(f'\t\t{MAIN_GROUP} = {{isa = PBXGroup; children = ({dir_id["."]}, {TEST_GROUP}, {APP_REF}, {TEST_BUNDLE_REF}); sourceTree = "<group>"; }};')

# --- Build phases ---
SRC_PHASE = uid("phase:sources")
A(f"\t\t{SRC_PHASE} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (")
for p in sources:
    A(f"\t\t\t{build_id(p)},")
A("\t\t); runOnlyForDeploymentPostprocessing = 0; };")
RES_PHASE = uid("phase:resources")
A(f"\t\t{RES_PHASE} = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (")
for p in resources:
    A(f"\t\t\t{build_id(p)},")
A("\t\t); runOnlyForDeploymentPostprocessing = 0; };")
FW_PHASE = uid("phase:frameworks")
A(f"\t\t{FW_PHASE} = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};")

# --- Test target build phases ---
TEST_SRC_PHASE = uid("testphase:sources")
A(f"\t\t{TEST_SRC_PHASE} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (")
for p in test_entries:
    A(f"\t\t\t{test_build_id(p)},")
A("\t\t); runOnlyForDeploymentPostprocessing = 0; };")
TEST_FW_PHASE = uid("testphase:frameworks")
A(f"\t\t{TEST_FW_PHASE} = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};")
TEST_RES_PHASE = uid("testphase:resources")
A(f"\t\t{TEST_RES_PHASE} = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};")

# --- Targets ---
TARGET = uid("target")
A(f"\t\t{TARGET} = {{isa = PBXNativeTarget; buildConfigurationList = {uid('cfglist:target')}; buildPhases = ({SRC_PHASE}, {FW_PHASE}, {RES_PHASE}); buildRules = (); dependencies = (); name = Soma; productName = Soma; productReference = {APP_REF}; productType = \"com.apple.product-type.application\"; }};")
TEST_TARGET = uid("target:test")
TEST_DEP = uid("testdep")
TEST_PROXY = uid("testproxy")
A(f"\t\t{TEST_PROXY} = {{isa = PBXContainerItemProxy; containerPortal = {uid('project')}; proxyType = 1; remoteGlobalIDString = {TARGET}; remoteInfo = Soma; }};")
A(f"\t\t{TEST_DEP} = {{isa = PBXTargetDependency; target = {TARGET}; targetProxy = {TEST_PROXY}; }};")
A(f"\t\t{TEST_TARGET} = {{isa = PBXNativeTarget; buildConfigurationList = {uid('cfglist:testtarget')}; buildPhases = ({TEST_SRC_PHASE}, {TEST_FW_PHASE}, {TEST_RES_PHASE}); buildRules = (); dependencies = ({TEST_DEP}); name = SomaTests; productName = SomaTests; productReference = {TEST_BUNDLE_REF}; productType = \"com.apple.product-type.bundle.unit-test\"; }};")

# --- Project ---
PROJECT = uid("project")
A(f"\t\t{PROJECT} = {{isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; TargetAttributes = {{ {TARGET} = {{ CreatedOnToolsVersion = 16.0; }}; {TEST_TARGET} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {TARGET}; }}; }}; }}; buildConfigurationList = {uid('cfglist:project')}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en); mainGroup = {MAIN_GROUP}; productRefGroup = {MAIN_GROUP}; projectDirPath = \"\"; projectRoot = \"\"; targets = ({TARGET}, {TEST_TARGET}); }};")


def xcconfig(key, name, settings):
    A(f"\t\t{uid('cfg:' + key)} = {{isa = XCBuildConfiguration; buildSettings = {{")
    for k, v in settings.items():
        A(f"\t\t\t{k} = {v};")
    A(f"\t\t}}; name = {name}; }};")


common_target = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "CODE_SIGN_ENTITLEMENTS": '"Soma/Soma.entitlements"',
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": '"Soma/Info.plist"',
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": '"com.michaelchu.soma"',
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": '"1"',
}
xcconfig("project-Debug", "Debug", {"ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES"})
xcconfig("project-Release", "Release", {"ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES"})
dbg = dict(common_target); dbg["SWIFT_OPTIMIZATION_LEVEL"] = '"-Onone"'
dbg["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
dbg["ENABLE_TESTABILITY"] = "YES"
xcconfig("target-Debug", "Debug", dbg)
xcconfig("target-Release", "Release", dict(common_target))

# Test target configs (logic tests; @testable import needs the app's testability above)
common_test = {
    "BUNDLE_LOADER": '"$(TEST_HOST)"',
    "CODE_SIGN_STYLE": "Automatic",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "PRODUCT_BUNDLE_IDENTIFIER": '"com.michaelchu.soma.tests"',
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": '"1"',
    "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/Soma.app/Soma"',
}
test_dbg = dict(common_test); test_dbg["SWIFT_OPTIMIZATION_LEVEL"] = '"-Onone"'
test_dbg["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
xcconfig("testtarget-Debug", "Debug", test_dbg)
xcconfig("testtarget-Release", "Release", dict(common_test))

for kind, cfgs in (("project", ["project-Debug", "project-Release"]), ("target", ["target-Debug", "target-Release"]), ("testtarget", ["testtarget-Debug", "testtarget-Release"])):
    ids = ", ".join(uid("cfg:" + c) for c in cfgs)
    A(f"\t\t{uid('cfglist:' + kind)} = {{isa = XCConfigurationList; buildConfigurations = ({ids}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};")

A("\t};")
A(f"\trootObject = {PROJECT};")
A("}")

os.makedirs(PROJDIR, exist_ok=True)
with open(os.path.join(PROJDIR, "project.pbxproj"), "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"wrote {len(sources)} sources, {len(resources)} resources")
