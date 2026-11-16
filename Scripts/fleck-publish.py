#!/usr/bin/env python3
"""Publish a staged Fleck.app with a no-replace rename.

The prebuilt-input path cannot compile the Swift publication helper, so it uses
`renamex_np(RENAME_EXCL)` directly: the rename fails when the destination
exists instead of moving the staged app inside an existing directory, which
`mv -n` would do.
"""
import argparse
import ctypes
import ctypes.util
import errno
import os
import sys

RENAME_EXCL = 0x4


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def rename_exclusive(source, destination):
    libc_path = ctypes.util.find_library("c") or "/usr/lib/libSystem.B.dylib"
    try:
        libc = ctypes.CDLL(libc_path, use_errno=True)
    except OSError as error:
        fail(f"could not load libc: {error}")
    rename = libc.renamex_np
    rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(os.fsencode(source), os.fsencode(destination), RENAME_EXCL) == 0:
        return
    code = ctypes.get_errno()
    if code == errno.EEXIST:
        fail(f"refusing to overwrite an existing destination: {destination}")
    fail(f"could not publish {destination}: {os.strerror(code)}")


def publish(source, destination):
    for label, value in (("source", source), ("destination", destination)):
        if not value.startswith("/"):
            fail(f"{label} must be an absolute path")
        if os.path.normpath(value) != value:
            fail(f"{label} must be a normalized path")
    if os.path.islink(source) or not os.path.isdir(source):
        fail(f"staged app must be a real directory: {source}")
    rename_exclusive(source, destination)


def parser():
    result = argparse.ArgumentParser(
        description="Publish a staged Fleck.app without replacing an existing destination"
    )
    result.add_argument("--source", required=True)
    result.add_argument("--destination", required=True)
    return result


def main():
    args = parser().parse_args()
    publish(args.source, args.destination)


if __name__ == "__main__":
    main()
