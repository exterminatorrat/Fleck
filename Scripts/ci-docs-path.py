#!/usr/bin/env python3
import argparse
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import stat
import subprocess
import sys
from urllib.parse import unquote, urlsplit


GIT_SHA = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
PRODUCT_VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*)?$")
MARKDOWN_LINK = re.compile(r"!?\[[^\]]*\]\(\s*(<[^>]+>|[^)\s]+)(?:\s+['\"][^)]*['\"])?\s*\)")
LEGACY_BRAND_TERMS = ("menubar" + "notes",)


class ValidationError(ValueError):
    pass


def git(repository, *arguments):
    result = subprocess.run(
        ("git", *arguments),
        cwd=repository,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise ValidationError("git source verification failed")
    return result.stdout


def repository_identity(repository, source_commit):
    repository = Path(repository).resolve()
    if not GIT_SHA.fullmatch(source_commit):
        raise ValidationError("invalid source commit")
    commit = git(repository, "rev-parse", "--verify", "HEAD^{commit}").decode("ascii").strip()
    if commit != source_commit:
        raise ValidationError("checked-out source commit does not match GitHub SHA")
    if git(repository, "status", "--porcelain=v1", "-z", "--untracked-files=all"):
        raise ValidationError("checked-out source is not clean")
    tree = git(repository, "rev-parse", "--verify", "HEAD^{tree}").decode("ascii").strip()
    version_path = repository / "VERSION"
    workflow_path = repository / ".github/workflows/ci.yml"
    if not stat.S_ISREG(version_path.lstat().st_mode):
        raise ValidationError("VERSION must be a regular file")
    if not stat.S_ISREG(workflow_path.lstat().st_mode):
        raise ValidationError("CI workflow must be a regular file")
    version = version_path.read_text(encoding="ascii").strip()
    if not PRODUCT_VERSION.fullmatch(version):
        raise ValidationError("invalid product version")
    workflow_sha256 = hashlib.sha256(workflow_path.read_bytes()).hexdigest()
    return {
        "source_commit": commit,
        "source_tree": tree,
        "product_version": version,
        "workflow_sha256": workflow_sha256,
    }


def classify_name_status(output):
    if not output or not output.endswith(b"\0"):
        return "full"
    fields = output[:-1].split(b"\0")
    records = []
    position = 0
    while position < len(fields):
        try:
            status = fields[position].decode("ascii")
        except UnicodeDecodeError:
            return "full"
        position += 1
        if re.fullmatch(r"[RC][0-9]{1,3}", status):
            count = 2
        elif status in {"A", "D", "M", "T", "U", "X", "B"}:
            count = 1
        else:
            return "full"
        paths = tuple(fields[position : position + count])
        if len(paths) != count or any(not path for path in paths):
            return "full"
        position += count
        records.append((status, paths))
    if not records:
        return "full"
    if len(records) == 1 and records[0][0] in {"A", "M"} and records[0][1] == (b"README.md",):
        return "docs"
    return "full"


def classify_pull_request(repository, source_commit, event):
    pull_request = event.get("pull_request") if isinstance(event, dict) else None
    if not isinstance(pull_request, dict):
        return "full"
    base = pull_request.get("base")
    head = pull_request.get("head")
    base_sha = base.get("sha") if isinstance(base, dict) else None
    head_sha = head.get("sha") if isinstance(head, dict) else None
    if not isinstance(base_sha, str) or not GIT_SHA.fullmatch(base_sha):
        return "full"
    if not isinstance(head_sha, str) or not GIT_SHA.fullmatch(head_sha):
        return "full"
    parents = git(repository, "rev-list", "--parents", "-n", "1", source_commit).decode("ascii").split()
    if parents != [source_commit, base_sha, head_sha]:
        return "full"
    for commit in (base_sha, head_sha):
        if subprocess.run(
            ("git", "cat-file", "-e", f"{commit}^{{commit}}"),
            cwd=repository,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode != 0:
            return "full"
    merge_bases = git(repository, "merge-base", "--all", base_sha, head_sha).decode("ascii").split()
    if len(merge_bases) != 1 or not GIT_SHA.fullmatch(merge_bases[0]):
        return "full"
    diff = subprocess.run(
        (
            "git",
            "diff",
            "--no-ext-diff",
            "--no-textconv",
            "--name-status",
            "-z",
            "--find-renames=50%",
            merge_bases[0],
            head_sha,
            "--",
        ),
        cwd=repository,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if diff.returncode != 0:
        return "full"
    return classify_name_status(diff.stdout)


def classify(repository, event_name, event_path, source_commit):
    identity = repository_identity(repository, source_commit)
    route = "full"
    if event_name == "pull_request":
        try:
            event = json.loads(Path(event_path).read_text(encoding="utf-8"))
            route = classify_pull_request(repository, source_commit, event)
        except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValidationError):
            route = "full"
    return route, identity


class HTMLReferences(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.targets = []

    def handle_starttag(self, tag, attributes):
        for name, value in attributes:
            if name.lower() in {"href", "src"} and value is not None:
                self.targets.append(value)

    def handle_startendtag(self, tag, attributes):
        self.handle_starttag(tag, attributes)


def validate_local_reference(repository, target):
    try:
        parsed = urlsplit(target.strip())
    except ValueError as error:
        raise ValidationError("README contains an invalid link") from error
    if parsed.scheme or parsed.netloc or not parsed.path:
        return
    repository = Path(repository).resolve()
    candidate = (repository / unquote(parsed.path)).resolve()
    try:
        candidate.relative_to(repository)
    except ValueError as error:
        raise ValidationError("README links must stay inside the repository") from error
    if not candidate.exists():
        raise ValidationError("README contains a broken local link")


def validate_readme(repository):
    repository = Path(repository).resolve()
    readme = repository / "README.md"
    if not stat.S_ISREG(readme.lstat().st_mode):
        raise ValidationError("README.md must be a regular file")
    data = readme.read_bytes()
    if not data or b"\0" in data:
        raise ValidationError("README.md must be nonempty UTF-8 text")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ValidationError("README.md must be valid UTF-8") from error
    if not text.strip():
        raise ValidationError("README.md must not be blank")
    if re.search(r"(?m)^(?:<{7,}(?: |$)|={7,}$|>{7,}(?: |$))", text):
        raise ValidationError("README.md contains a conflict marker")
    if "Agent Connector" not in text:
        raise ValidationError("README.md is missing required Agent Connector documentation")
    lowered = text.casefold()
    if "command bridge" in lowered:
        raise ValidationError("README.md contains a forbidden legacy term")
    if any(term in lowered for term in LEGACY_BRAND_TERMS):
        raise ValidationError("README.md contains a forbidden legacy brand term")
    references = [match.group(1).strip("<>") for match in MARKDOWN_LINK.finditer(text)]
    html_references = HTMLReferences()
    html_references.feed(text)
    references.extend(html_references.targets)
    for target in references:
        validate_local_reference(repository, target)


def validate_documentation(repository, source_commit, expected):
    identity = repository_identity(repository, source_commit)
    if identity != expected:
        raise ValidationError("documentation validation source identity drifted")
    validate_readme(repository)
    return identity


def write_outputs(path, values):
    for value in values.values():
        if not isinstance(value, str) or "\n" in value or "\r" in value:
            raise ValidationError("invalid workflow output")
    with Path(path).open("a", encoding="utf-8") as output:
        for name, value in values.items():
            output.write(f"{name}={value}\n")


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    detect_parser = subparsers.add_parser("classify")
    detect_parser.add_argument("--repository", required=True)
    detect_parser.add_argument("--event-name", required=True)
    detect_parser.add_argument("--event-file", required=True)
    detect_parser.add_argument("--source-commit", required=True)
    detect_parser.add_argument("--output", required=True)
    validate_parser = subparsers.add_parser("validate")
    validate_parser.add_argument("--repository", required=True)
    validate_parser.add_argument("--source-commit", required=True)
    validate_parser.add_argument("--expected-commit", required=True)
    validate_parser.add_argument("--expected-tree", required=True)
    validate_parser.add_argument("--expected-version", required=True)
    validate_parser.add_argument("--expected-workflow-sha256", required=True)
    validate_parser.add_argument("--output", required=True)
    arguments = parser.parse_args()
    try:
        if arguments.command == "classify":
            route, identity = classify(
                arguments.repository,
                arguments.event_name,
                arguments.event_file,
                arguments.source_commit,
            )
            write_outputs(arguments.output, {"route": route, **identity})
            print(f"CI route: {route}")
            return 0
        expected = {
            "source_commit": arguments.expected_commit,
            "source_tree": arguments.expected_tree,
            "product_version": arguments.expected_version,
            "workflow_sha256": arguments.expected_workflow_sha256,
        }
        identity = validate_documentation(arguments.repository, arguments.source_commit, expected)
        write_outputs(arguments.output, identity)
        print("README documentation validation passed")
        return 0
    except (OSError, UnicodeError, ValidationError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
