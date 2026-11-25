"""Exercise incremental icon packaging without compiling or closing the real app.

Run with: python3 -m unittest discover -s Tests/BuildScriptTests -v
Fixtures are kept in the OS temporary directory for inspection.
"""

import hashlib
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
        swift = binaries / "swift"
        swift.write_text('#!/bin/sh\ncase " $* " in\n'
                         '  *" --configuration release "*" --show-bin-path "*) printf "%s\\n" "$RELEASE_BIN_PATH";;\n'
                         '  *" --show-bin-path "*) printf "%s\\n" "$SHOW_BIN_PATH";;\n'
                         '  *) exit 0;;\nesac\n')
        swift.chmod(0o755)
        # Model the packaging contracts without invoking signing or changing
        # any running app. The icon assertions below exercise the real script.
        strip = binaries / "strip"
        strip.write_text('#!/bin/sh\n[ "$1" = "-S" ] && [ "$2" = "-x" ] || exit 1\n'
                         'shasum -a 256 "$3" | awk \'{print $1}\' > "$STRIP_LOG"\n'
                         'printf "bin\\n" > "$3"\n')
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
        subprocess.run(["clang", "-x", "c", "-o", str(executable), "-"],
                       input="int main(void) { return 0; }\n", text=True, check=True)
        resources = product / "XTools_XToolsCore.bundle/Contents/Resources"
        resources.mkdir(parents=True)
        (resources / "Readability-0.6.0.js").write_text("// fixture\n")
        compiler_bundle = product / "XTools_EmojiCatalogCompiler.bundle"
        compiler_bundle.mkdir()
        (compiler_bundle / "emoji-test.txt").write_text("compiler input only\n")
        app_resources = product / "XTools_XTools.bundle/Contents/Resources"
        language = app_resources / "zh-Hans.lproj"
        language.mkdir(parents=True)
        (app_resources / "asset.txt").write_text("keep this resource")
        source_table = language / "Localizable.strings"
        source_table.write_bytes(plistlib.dumps({"key": "中文"}))
        source = fixture / "Assets/AppIcon/XTools.icns"
        source.parent.mkdir(parents=True)
        source.write_bytes(b"first-icon")
        log = fixture / "register.log"
        strip_log = fixture / "strip.log"
        environment = dict(os.environ, PATH=f"{binaries}:{os.environ['PATH']}",
                           SWIFT_BIN=str(binaries / "swift"), LSREGISTER=str(register),
                           ARCH=os.uname().machine,
                           BUNDLE_ID="com.sun.xtools.icon-test", KEEP_RUNNING_APP="1",
                           OUTPUT_DIR=str(fixture / "build"),
                           SHOW_BIN_PATH=str(product), RELEASE_BIN_PATH=str(fixture / "missing-release"),
                           STRIP_LOG=str(strip_log), REGISTER_LOG=str(log), LSREGISTER_EVERY_BUILD="0",
                           TRASH_DIR=str(fixture / "archive"))

        def package(*arguments):
            result = subprocess.run(["bash", str(fixture / "build.sh"), "package", *arguments],
                                    env=environment, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

        package()
        app = fixture / "build/XTools.app"
        packaged = app / "Contents/Resources/XTools.icns"
        self.assertEqual(packaged.read_bytes(), b"first-icon")
        packaged_resources = app / "Contents/Resources"
        packaged_bundle_resources = packaged_resources / "XTools_XTools.bundle/Contents/Resources"
        packaged_table = packaged_resources / "zh-Hans.lproj/Localizable.strings"
        self.assertEqual(plistlib.loads(packaged_table.read_bytes()), {"key": "中文"})
        self.assertTrue(packaged_table.read_bytes().startswith(b"bplist00"))
        self.assertFalse((packaged_bundle_resources / language.name).exists())
        self.assertEqual((packaged_bundle_resources / "asset.txt").read_text(), "keep this resource")
        self.assertFalse((app / "Contents/Resources" / compiler_bundle.name).exists(),
                         "Offline compiler inputs must not ship with the app")
        stale_compiler = app / "Contents/Resources" / compiler_bundle.name
        shutil.copytree(compiler_bundle, stale_compiler)
        shutil.copytree(language, packaged_bundle_resources / language.name)
        (packaged_table.parent / "Retired.strings").write_bytes(plistlib.dumps({"old": "旧"}))
        source_table.write_bytes(plistlib.dumps({"key": "更新"}))
        info_plist = app / "Contents/Info.plist"
        stale_metadata = plistlib.loads(info_plist.read_bytes())
        stale_metadata["CFBundleDisplayName"] = "Old name"
        info_plist.write_bytes(plistlib.dumps(stale_metadata))
        source.write_bytes(b"replacement-icon")
        package()
        self.assertFalse(stale_compiler.exists(),
                         "Incremental packaging must archive old compiler bundles")
        self.assertTrue(any((fixture / "archive").glob(f"{compiler_bundle.name}.*")))
        self.assertEqual(packaged.read_bytes(), b"replacement-icon",
                         "An existing app must receive changed icon content")
        self.assertFalse((packaged_bundle_resources / language.name).exists())
        self.assertFalse((packaged_table.parent / "Retired.strings").exists())
        self.assertEqual(plistlib.loads(packaged_table.read_bytes()), {"key": "更新"})
        metadata = plistlib.loads(info_plist.read_bytes())
        self.assertEqual(metadata["CFBundleIconFile"], "XTools")
        self.assertEqual(metadata["CFBundleDisplayName"], "XTools")
        self.assertTrue(metadata["NSAppTransportSecurity"]["NSAllowsArbitraryLoads"])
        self.assertEqual(log.read_text().splitlines(), ["registered", "registered"])

        modified_at = packaged.stat().st_mtime_ns
        unchanged_metadata = info_plist.stat().st_mtime_ns
        unchanged_table = packaged_table.stat().st_mtime_ns
        package()
        self.assertEqual(packaged.stat().st_mtime_ns, modified_at,
                         "Unchanged icons must not be rewritten")
        self.assertEqual(len(log.read_text().splitlines()), 2,
                         "Unchanged icons must not trigger registration")
        self.assertEqual(info_plist.stat().st_mtime_ns, unchanged_metadata)
        self.assertEqual(packaged_table.stat().st_mtime_ns, unchanged_table)

        cold_product = fixture / "swiftpm-cold-product"
        product.rename(cold_product)
        environment["SHOW_BIN_PATH"] = str(cold_product)
        product.mkdir()
        stale = product / "XTools"
        subprocess.run(["clang", "-x", "c", "-o", str(stale), "-"],
                       input="int main(void) { return 41; }\n", text=True, check=True)
        package("debug")
        self.assertEqual(strip_log.read_text().strip(),
                         hashlib.sha256((cold_product / "XTools").read_bytes()).hexdigest())

        wrong_product = fixture / "wrong-architecture"
        wrong_product.mkdir()
        wrong_arch = "x86_64" if os.uname().machine == "arm64" else "arm64"
        subprocess.run(["clang", "-arch", wrong_arch, "-x", "c", "-o", str(wrong_product / "XTools"), "-"],
                       input="int main(void) { return 0; }\n", text=True, check=True)
        mismatch = subprocess.run(["bash", str(fixture / "build.sh"), "package", "debug"],
                                  env={**environment, "SHOW_BIN_PATH": str(wrong_product)},
                                  text=True, capture_output=True)
        self.assertNotEqual(mismatch.returncode, 0)
        self.assertIn(f"does not contain {os.uname().machine}", mismatch.stderr)
        environment["SHOW_BIN_PATH"] = str(cold_product)

        source.rename(source.with_suffix(".archived"))
        missing = subprocess.run(["bash", str(fixture / "build.sh"), "package"],
                                 env=environment, text=True, capture_output=True)
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("Missing app icon", missing.stdout + missing.stderr)
        self.assertEqual(packaged.read_bytes(), b"replacement-icon")


if __name__ == "__main__":
    unittest.main()
