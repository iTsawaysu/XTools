"""Exercise package creation, incremental resources, and recovery with fixture apps.

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
    def test_fallback_restores_previous_directory_if_candidate_move_fails(self):
        repository = Path(__file__).resolve().parents[2]
        fixture = Path(tempfile.mkdtemp(prefix="xtools-package-recovery-"))
        prior = fixture / "XTools.app"
        prior.mkdir()
        (prior / "keep.txt").write_text("previous output")
        script = fixture / "rollback.js"
        script.write_text((repository / "tools/packaging-app.js").read_text() + """
function run(argv) {
    publishByMoving(argv[0], argv[1], true);
}
""")
        result = subprocess.run(["/usr/bin/osascript", "-l", "JavaScript", str(script),
                                 str(fixture / "absent-candidate.app"), str(prior)],
                                text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((prior / "keep.txt").read_text(), "previous output")

    def test_incremental_icon_replacement_and_unchanged_fast_path(self):
        repository = Path(__file__).resolve().parents[2]
        fixture = Path(tempfile.mkdtemp(prefix="xtools-icon-packaging-"))
        shutil.copy2(repository / "build.sh", fixture / "build.sh")
        for relative in ("tools/packaging-app.js", "tools/ui-lint.py",
                         "Sources/XTools/Resources/Localizable.xcstrings"):
            target = fixture / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(repository / relative, target)
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
                         '[ "${FAIL_STRIP:-}" != 1 ] || exit 48\n'
                         'shasum -a 256 "$3" | awk \'{print $1}\' > "$STRIP_LOG"\n'
                         'printf "bin\\n" > "$3"\n')
        strip.chmod(0o755)
        codesign = binaries / "codesign"
        codesign.write_text('#!/bin/sh\n'
                            '[ "${FAIL_SIGN:-}" != 1 ] || [ "$1" != "--force" ] || exit 49\n'
                            'if [ "${REPLACE_DESTINATION:-}" = 1 ] && [ "$1" = "--verify" ]; then\n'
                            '  mv "$OUTPUT_DIR/XTools.app" "$OUTPUT_DIR/prior.app" || exit 51\n'
                            '  mkdir "$OUTPUT_DIR/XTools.app" || exit 52\n'
                            '  printf "foreign" > "$OUTPUT_DIR/XTools.app/keep.txt"\n'
                            'fi\n'
                            'if [ "$1" = "-dv" ]; then\n  printf "Identifier=%s\\n" "$BUNDLE_ID" >&2\nfi\n')
        codesign.chmod(0o755)
        osascript = binaries / "osascript"
        osascript.write_text('#!/bin/sh\n'
                             'if [ "$4" = "launch" ]; then printf "%s|%s\\n" "$5" "$7" >> "$LAUNCH_LOG"; exit; fi\n'
                             '[ "${FAIL_PUBLISH:-}" != 1 ] || [ "$4" != "publish" ] || exit 50\n'
                             'exec /usr/bin/osascript "$@"\n')
        osascript.chmod(0o755)
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
        (resources / "emoji-catalog-v1.plist").write_bytes(plistlib.dumps({"catalog": "fixture"}))
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
        launch_log = fixture / "launch.log"
        strip_log = fixture / "strip.log"
        environment = dict(os.environ, PATH=f"{binaries}:{os.environ['PATH']}",
                           SWIFT_BIN=str(binaries / "swift"), LSREGISTER=str(register),
                           ARCH=os.uname().machine,
                           BUNDLE_ID="com.sun.xtools.icon-test", KEEP_RUNNING_APP="1",
                           OUTPUT_DIR=str(fixture / "build"),
                           SHOW_BIN_PATH=str(product), RELEASE_BIN_PATH=str(fixture / "missing-release"),
                           STRIP_LOG=str(strip_log),
                           LAUNCH_LOG=str(launch_log),
                           REGISTER_LOG=str(log), LSREGISTER_EVERY_BUILD="0",
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
        self.assertEqual((packaged_resources / "XToolsCore/Readability-0.6.0.js").read_text(), "// fixture\n")
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
        self.assertTrue(any((fixture / "archive").glob(
            f"xtools-package.*/XTools.app/Contents/Resources/{compiler_bundle.name}"
        )))
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

        for arguments, launch_environment in (
            (["dev"], environment),
            ([], {**environment, "RELEASE_BIN_PATH": str(product),
                  "OUTPUT_DIR": str(fixture / "release-launch"), "KEEP_RUNNING_APP": ""}),
        ):
            command = [str(fixture / "build.sh"), *arguments]
            subprocess.run(command, env=launch_environment, check=True, capture_output=True)
            archive = sorted((fixture / "archive").iterdir())
            unchanged = subprocess.run(command, env={**launch_environment, "FAIL_STRIP": "1"},
                                       check=True, capture_output=True, text=True)
            self.assertIn("Up to date", unchanged.stdout)
            self.assertEqual(sorted((fixture / "archive").iterdir()), archive)
            target = Path(launch_environment["OUTPUT_DIR"]) / "XTools.app"
            may_stop = "no" if launch_environment["KEEP_RUNNING_APP"] else "yes"
            self.assertEqual(launch_log.read_text().splitlines()[-2:], [f"{target}|{may_stop}"] * 2)

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

        previous_metadata = info_plist.read_bytes()
        source.write_bytes(b"unpublished-icon")
        for failure in ("FAIL_STRIP", "FAIL_SIGN", "FAIL_PUBLISH"):
            failed = subprocess.run([str(fixture / "build.sh"), "package", "debug"],
                                    env={**environment, failure: "1"}, text=True, capture_output=True)
            self.assertNotEqual(failed.returncode, 0, failed.stdout + failed.stderr)
            self.assertEqual(packaged.read_bytes(), b"replacement-icon")
            self.assertEqual(info_plist.read_bytes(), previous_metadata)

        bad_archive = subprocess.run([str(fixture / "build.sh"), "package", "debug"],
                                     env={**environment, "TRASH_DIR": str(app / "Contents/Resources/archive")},
                                     text=True, capture_output=True)
        self.assertNotEqual(bad_archive.returncode, 0)
        self.assertFalse((app / "Contents/Resources/archive").exists())
        self.assertEqual(info_plist.read_bytes(), previous_metadata)

        replaced = subprocess.run([str(fixture / "build.sh"), "package", "debug"],
                                  env={**environment, "REPLACE_DESTINATION": "1"}, text=True, capture_output=True)
        self.assertNotEqual(replaced.returncode, 0)
        self.assertIn("destination changed", replaced.stderr.lower())
        self.assertEqual((app / "keep.txt").read_text(), "foreign")
        app.rename(fixture / "foreign.app")
        app.with_name("prior.app").rename(app)
        self.assertEqual(info_plist.read_bytes(), previous_metadata)

        blocked_archive = fixture / "archive-is-a-file"
        blocked_archive.write_text("unrelated")
        archived_locally = subprocess.run([str(fixture / "build.sh"), "package", "debug"],
                                          env={**environment, "TRASH_DIR": str(blocked_archive)},
                                          check=True, text=True, capture_output=True)
        self.assertIn("Kept packaging work", archived_locally.stderr)
        self.assertEqual(packaged.read_bytes(), b"unpublished-icon")
        self.assertEqual(blocked_archive.read_text(), "unrelated")
        kept = fixture / "build"
        self.assertTrue(any(path.read_bytes() == b"replacement-icon" for path in kept.glob(
            ".xtools-package.*/XTools.app/Contents/Resources/XTools.icns"
        )))

        native = fixture / "native-product"
        native.mkdir()
        shutil.copy2(cold_product / "XTools", native / "XTools")
        shutil.copytree(cold_product / resources.relative_to(product), native / "XTools_XToolsCore.bundle")
        native_app = native / "XTools_XTools.bundle"
        native_app.mkdir()
        shutil.copy2(repository / "Sources/XTools/Resources/Localizable.xcstrings", native_app)
        environment["SHOW_BIN_PATH"] = str(native)
        package("debug")
        self.assertIn("复制", plistlib.loads(packaged_table.read_bytes()))
        self.assertTrue(packaged_table.read_bytes().startswith(b"bplist00"))
        self.assertFalse(list(packaged_resources.rglob("*.xcstrings")))

        neighbor = fixture / "build/keep.txt"
        neighbor.write_text("unrelated")
        subprocess.run([str(fixture / "build.sh"), "clean"], env=environment, check=True, capture_output=True)
        self.assertEqual(neighbor.read_text(), "unrelated")
        self.assertFalse(app.exists())


if __name__ == "__main__":
    unittest.main()
