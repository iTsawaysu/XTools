"""Exercise incremental icon packaging without compiling or closing the real app.

Run with: python3 -m unittest discover -s Tests/BuildScriptTests -v
Fixtures are kept in the OS temporary directory for inspection.
"""

import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest


class IconPackagingTests(unittest.TestCase):
    def test_incremental_icon_replacement_and_unchanged_fast_path(self):
        repository = Path(__file__).resolve().parents[2]
        fixture = Path(tempfile.mkdtemp(prefix="xtools-icon-packaging-"))
        shutil.copy2(repository / "build.sh", fixture / "build.sh")
        binaries = fixture / "mock-bin"
        binaries.mkdir()
        for name in ("pkill", "swift"):
            executable = binaries / name
            executable.write_text("#!/bin/sh\nexit 0\n")
            executable.chmod(0o755)
        # Model the packaging contracts without invoking signing or changing
        # any running app. The icon assertions below exercise the real script.
        strip = binaries / "strip"
        strip.write_text('#!/bin/sh\n[ "$1" = "-S" ] && [ "$2" = "-x" ] || exit 1\nprintf "bin\\n" > "$3"\n')
        strip.chmod(0o755)
        codesign = binaries / "codesign"
        codesign.write_text('#!/bin/sh\nif [ "$1" = "-dv" ]; then\n  printf "Identifier=%s\\n" "$BUNDLE_ID" >&2\nfi\n')
        codesign.chmod(0o755)
        register = binaries / "lsregister"
        register.write_text('#!/bin/sh\nprintf "registered\\n" >> "$REGISTER_LOG"\n')
        register.chmod(0o755)

        product = fixture / ".build/debug"
        product.mkdir(parents=True)
        executable = product / "XTools"
        executable.write_text("#!/bin/sh\nexit 0\n")
        executable.chmod(0o755)
        resources = product / "XTools_XToolsCore.bundle/Contents/Resources"
        resources.mkdir(parents=True)
        (resources / "Readability-0.6.0.js").write_text("// fixture\n")
        compiler_bundle = product / "XTools_EmojiCatalogCompiler.bundle"
        compiler_bundle.mkdir()
        (compiler_bundle / "emoji-test.txt").write_text("compiler input only\n")
        source = fixture / "Assets/AppIcon/XTools.icns"
        source.parent.mkdir(parents=True)
        source.write_bytes(b"first-icon")
        log = fixture / "register.log"
        environment = dict(os.environ, PATH=f"{binaries}:{os.environ['PATH']}",
                           SWIFT_BIN=str(binaries / "swift"), LSREGISTER=str(register),
                           BUNDLE_ID="com.sun.xtools.icon-test", KEEP_RUNNING_APP="1",
                           OUTPUT_DIR=str(fixture / "build"),
                           REGISTER_LOG=str(log), LSREGISTER_EVERY_BUILD="0",
                           TRASH_DIR=str(fixture / "archive"))

        def package():
            result = subprocess.run(["bash", str(fixture / "build.sh"), "package"],
                                    env=environment, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

        package()
        app = fixture / "build/XTools.app"
        packaged = app / "Contents/Resources/XTools.icns"
        self.assertEqual(packaged.read_bytes(), b"first-icon")
        self.assertFalse((app / "Contents/Resources" / compiler_bundle.name).exists(),
                         "Offline compiler inputs must not ship with the app")
        stale_compiler = app / "Contents/Resources" / compiler_bundle.name
        shutil.copytree(compiler_bundle, stale_compiler)
        source.write_bytes(b"replacement-icon")
        package()
        self.assertFalse(stale_compiler.exists(),
                         "Incremental packaging must archive old compiler bundles")
        self.assertTrue(any((fixture / "archive").glob(f"{compiler_bundle.name}.*")))
        self.assertEqual(packaged.read_bytes(), b"replacement-icon",
                         "An existing app must receive changed icon content")
        metadata = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        self.assertEqual(metadata["CFBundleIconFile"], "XTools")
        self.assertEqual(log.read_text().splitlines(), ["registered", "registered"])

        modified_at = packaged.stat().st_mtime_ns
        package()
        self.assertEqual(packaged.stat().st_mtime_ns, modified_at,
                         "Unchanged icons must not be rewritten")
        self.assertEqual(len(log.read_text().splitlines()), 2,
                         "Unchanged icons must not trigger registration")

        source.rename(source.with_suffix(".archived"))
        missing = subprocess.run(["bash", str(fixture / "build.sh"), "package"],
                                 env=environment, text=True, capture_output=True)
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("Missing app icon", missing.stdout + missing.stderr)
        self.assertEqual(packaged.read_bytes(), b"replacement-icon")


if __name__ == "__main__":
    unittest.main()
