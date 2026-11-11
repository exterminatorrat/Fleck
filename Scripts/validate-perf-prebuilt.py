#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path


RECEIPT_FIELDS = {
    "schemaVersion",
    "packageRoot",
    "sourceCommit",
    "sourceTree",
    "configuration",
    "buildSystem",
    "testabilityEnabled",
    "swiftVersion",
    "sdkVersion",
    "harnessSHA256",
    "bootstrapWrapperSHA256",
    "testBundleExecutableSHA256",
}
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
SDK_VERSION = re.compile(r"^[0-9]+(?:\.[0-9]+)*$")


class ValidationError(Exception):
    pass


class ArgumentParser(argparse.ArgumentParser):
    def error(self, _message):
        raise ValidationError("error: invalid arguments")


def canonical_path(value, category):
    if not value.startswith("/") or "\n" in value or "\r" in value:
        raise ValidationError(category)
    path = Path(value)
    if str(path) != value:
        raise ValidationError(category)
    try:
        if path.resolve(strict=True) != path:
            raise ValidationError(category)
    except (OSError, RuntimeError):
        raise ValidationError(category) from None
    return path


def required_file(path, category):
    if not path.is_file():
        raise ValidationError(category)
    return path


def sha256(path, category):
    try:
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
        return digest.hexdigest()
    except OSError:
        raise ValidationError(category) from None


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValidationError("error: invalid receipt")
        result[key] = value
    return result


def reject_constant(_value):
    raise ValidationError("error: invalid receipt")


def read_receipt(path):
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(
                handle,
                object_pairs_hook=unique_object,
                parse_constant=reject_constant,
            )
    except ValidationError:
        raise
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
        raise ValidationError("error: invalid receipt") from None


def run_git(root, *arguments):
    try:
        result = subprocess.run(
            ["git", "-C", str(root), *arguments],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError, UnicodeError):
        raise ValidationError("error: source verification failed") from None
    return result.stdout.strip()


def validate(args):
    if args.configuration not in ("debug", "release"):
        raise ValidationError("error: toolchain or configuration mismatch")
    if not args.swift_version or "\n" in args.swift_version or "\r" in args.swift_version:
        raise ValidationError("error: toolchain or configuration mismatch")
    if not SDK_VERSION.fullmatch(args.sdk_version):
        raise ValidationError("error: toolchain or configuration mismatch")

    receipt_path = canonical_path(args.receipt, "error: invalid receipt path")
    if receipt_path.suffix != ".json" or not receipt_path.is_file():
        raise ValidationError("error: invalid receipt path")
    root = canonical_path(args.package_root, "error: invalid package root")
    if not root.is_dir():
        raise ValidationError("error: invalid package root")

    expected_environment = {
        "FLECK_PERF_RUN": "1",
        "FLECK_TEST_SWIFT_TARGET": "FleckPerformanceTests",
        "FLECK_TEST_SWIFT_BUILD_SYSTEM": "swiftbuild",
        "FLECK_TEST_SWIFT_CONFIGURATION": args.configuration,
        "FLECK_PERF_PREBUILT_RECEIPT": args.receipt,
    }
    if any(os.environ.get(name) != value for name, value in expected_environment.items()) or \
        args.scratch_path or os.environ.get("FLECK_ENHANCED_CANDIDATE") == "1" or \
        os.environ.get("FLECK_BUILD_WITHOUT_SPARKLE") == "1" or \
        os.environ.get("FLECK_PERF_SWIFT_VERSION", args.swift_version) != args.swift_version:
        raise ValidationError("error: toolchain or configuration mismatch")

    try:
        script_path = Path(__file__)
        if not script_path.is_absolute():
            script_path = Path.cwd() / script_path
        script_path = canonical_path(str(script_path), "error: source verification failed")
        if script_path != root / "Scripts/validate-perf-prebuilt.py":
            raise ValidationError("error: source verification failed")
        if Path(run_git(root, "rev-parse", "--show-toplevel")).resolve(strict=True) != root:
            raise ValidationError("error: source verification failed")
        if run_git(root, "status", "--porcelain=v1", "--untracked-files=all"):
            raise ValidationError("error: source verification failed")
        commit = run_git(root, "rev-parse", "--verify", "HEAD")
        tree = run_git(root, "rev-parse", "--verify", "HEAD^{tree}")
        if not HEX40.fullmatch(commit) or not HEX40.fullmatch(tree):
            raise ValidationError("error: source verification failed")
    except (OSError, RuntimeError):
        raise ValidationError("error: source verification failed") from None

    receipt = read_receipt(receipt_path)
    if not isinstance(receipt, dict) or set(receipt) != RECEIPT_FIELDS or \
        type(receipt["schemaVersion"]) is not int or receipt["schemaVersion"] != 1 or \
        type(receipt["testabilityEnabled"]) is not bool or receipt["testabilityEnabled"] is not True:
        raise ValidationError("error: invalid receipt")
    if any(not isinstance(receipt[field], str) for field in RECEIPT_FIELDS - {
        "schemaVersion", "testabilityEnabled"
    }):
        raise ValidationError("error: invalid receipt")
    if any(not HEX64.fullmatch(receipt[field]) for field in (
        "harnessSHA256",
        "bootstrapWrapperSHA256",
        "testBundleExecutableSHA256",
    )):
        raise ValidationError("error: invalid receipt")
    if receipt["packageRoot"] != str(root) or receipt["sourceCommit"] != commit or \
        receipt["sourceTree"] != tree:
        raise ValidationError("error: receipt does not match current source")
    if receipt["configuration"] != args.configuration or receipt["buildSystem"] != "swiftbuild" or \
        receipt["swiftVersion"] != args.swift_version or receipt["sdkVersion"] != args.sdk_version:
        raise ValidationError("error: toolchain or configuration mismatch")

    harness = required_file(
        canonical_path(str(root / "Tests/Support/AppKitTestMain.swift"),
                       "error: source verification failed"),
        "error: source verification failed",
    )
    wrapper = required_file(
        canonical_path(str(root / "Scripts/run-swift-tests-with-appkit-host.sh"),
                       "error: source verification failed"),
        "error: source verification failed",
    )
    if sha256(harness, "error: source verification failed") != receipt["harnessSHA256"] or \
        sha256(wrapper, "error: source verification failed") != receipt["bootstrapWrapperSHA256"]:
        raise ValidationError("error: receipt does not match current source")

    products = root / ".build/out/Products" / args.configuration.capitalize()
    products = canonical_path(str(products), "error: performance bundle path is unsafe")
    if not products.is_dir():
        raise ValidationError("error: performance bundle path is unsafe")
    bundle = products / "FleckPerformanceTests.xctest"
    executable = bundle / "Contents/MacOS/FleckPerformanceTests"
    for path in (bundle, bundle / "Contents", bundle / "Contents/MacOS", executable):
        path = canonical_path(str(path), "error: performance bundle path is unsafe")
        if path == executable:
            required_file(path, "error: performance bundle path is unsafe")
        elif not path.is_dir():
            raise ValidationError("error: performance bundle path is unsafe")
    try:
        if not executable.stat().st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH):
            raise ValidationError("error: performance bundle path is unsafe")
    except OSError:
        raise ValidationError("error: performance bundle path is unsafe") from None
    if sha256(executable, "error: performance bundle executable does not match receipt") != \
        receipt["testBundleExecutableSHA256"]:
        raise ValidationError("error: performance bundle executable does not match receipt")
    return str(products)


def main():
    parser = ArgumentParser(add_help=False)
    parser.add_argument("--receipt", required=True)
    parser.add_argument("--package-root", required=True)
    parser.add_argument("--configuration", required=True)
    parser.add_argument("--swift-version", required=True)
    parser.add_argument("--sdk-version", required=True)
    parser.add_argument("--scratch-path", required=True)
    try:
        print(validate(parser.parse_args()))
    except ValidationError as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
