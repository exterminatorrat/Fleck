#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd -P)"
readonly repo_root="$(git -C "$script_dir/../../.." rev-parse --show-toplevel)"
readonly metadata="$repo_root/Tools/GemmaCleanupBenchmark/Metadata/gemma-3-1b-it-qat-4bit.json"
readonly corpus="$repo_root/Tools/GemmaCleanupBenchmark/Corpus/english-qualification-v1.json"
readonly source_corpus="$repo_root/Tools/QwenCleanupBenchmark/Qualification/corpus-v1.json"
readonly readme="$repo_root/Tools/GemmaCleanupBenchmark/README.md"

python3 -I -S - "$metadata" "$corpus" "$source_corpus" "$readme" <<'PY'
import copy
import hashlib
import json
import sys
from pathlib import Path


class ContractError(Exception):
    pass


def fail(message):
    raise ContractError(message)


def require(condition, message):
    if not condition:
        fail(message)


def load_json(path):
    def reject_duplicate_keys(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                fail(f"duplicate JSON key in {path}: {key}")
            result[key] = value
        return result

    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicate_keys)
    except FileNotFoundError:
        fail(f"missing required file: {path}")
    except json.JSONDecodeError as error:
        fail(f"invalid JSON in {path}: {error}")


def canonical_sha256(value):
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


EXPECTED_MODEL_REVISION = "15fed4eafb456c6fcb2a1165f19ac609670ed14b"
EXPECTED_MLX_SWIFT_LM_COMMIT = "bd4b7434e6bdb588c7ef55706ff8904cb7fd4c57"
EXPECTED_SOURCE_CORPUS_SHA256 = "6d8a639d6b67fde23a198398e13176ccc50af03acdfaf504a68dfaa20c9a17fb"
EXPECTED_LOCAL_USE_NOTICE = (
    "Local use constitutes acceptance of the Gemma Terms of Use at "
    "https://ai.google.dev/gemma/terms."
)
EXPECTED_REDISTRIBUTION_NOTICE = (
    "No distribution approval is granted. Any later redistribution requires a copy of "
    "the Gemma Terms of Use Agreement, the enforceable use restrictions, and the "
    "required Notice file."
)
EXPECTED_MODEL_FILES = [
    {
        "path": ".gitattributes",
        "bytes": 1570,
        "gitBlobOID": "52373fe24473b1aa44333d318f578ae6bf04b49b",
        "lfsOID": None,
        "xetHash": None,
    },
    {
        "path": "README.md",
        "bytes": 1202,
        "gitBlobOID": "fbadf314fb585ef189a5eb061e26537f92f7eade",
        "lfsOID": None,
        "xetHash": None,
    },
    {
        "path": "added_tokens.json",
        "bytes": 35,
        "gitBlobOID": "e17bde03d42feda32d1abfca6d3b598b9a020df7",
        "lfsOID": None,
        "xetHash": None,
    },
    {
        "path": "config.json",
        "bytes": 1105,
        "gitBlobOID": "1fbce929f85fe2ceb9bc6a216ec5ff93994ad287",
        "lfsOID": None,
        "xetHash": None,
    },
    {
        "path": "model.safetensors",
        "bytes": 732577304,
        "gitBlobOID": "b7c72ff4b32704c16afe1914706ac9ed94cc6291",
        "lfsOID": "b6010f6b03a83f973ca8708eb5784d5b0f80c0e7e9143dbb4c95d0eefe39c837",
        "xetHash": "558d22fc5d008bc20397be7d20103e9caac80d75598957fbdc2e64d7f40efa69",
    },
    {
        "path": "model.safetensors.index.json",
        "bytes": 50542,
        "gitBlobOID": "2edd34f24a81f4e2ae901417d17a08980614c92c",
        "lfsOID": None,
        "xetHash": None,
    },
    {
        "path": "special_tokens_map.json",
        "bytes": 662,
        "gitBlobOID": "1a6193244714d3d78be48666cb02cdbfac62ad86",
        "lfsOID": None,
        "xetHash": None,
    },
    {
        "path": "tokenizer.json",
        "bytes": 33384568,
        "gitBlobOID": "29401f984828a18bb09a6128d437c6766785eb66",
        "lfsOID": "4667f2089529e8e7657cfb6d1c19910ae71ff5f28aa7ab2ff2763330affad795",
        "xetHash": "fa66c8c017ade193f7cc37a2b421a1fc461563e803f179a496f7bdda2ec42c21",
    },
    {
        "path": "tokenizer.model",
        "bytes": 4689074,
        "gitBlobOID": "14f810a829755bae3fafd6f97096dbd2eac556bd",
        "lfsOID": "1299c11d7cf632ef3b4e11937501358ada021bbdf7c47638d13c0ee982f2e79c",
        "xetHash": "a81fa217b67ef4a1992b48a47651c27a2a19df419eafd1aad9c0bbd5ff49bde3",
    },
    {
        "path": "tokenizer_config.json",
        "bytes": 1156959,
        "gitBlobOID": "87a7b965259321cc01a7602329d13a1fb6d8cb14",
        "lfsOID": None,
        "xetHash": None,
    },
]

EXPECTED_QWEN_IDS = [f"qwen-asr-en_us-{index:02d}" for index in range(1, 13)]
EXPECTED_WHISPER_IDS = [f"whisper-asr-en_us-{index:02d}" for index in range(1, 13)]
EXPECTED_STRESS_IDS = [
    "stress-name-destination",
    "stress-number-words-digits",
    "stress-price-unit",
    "stress-date-time",
    "stress-url-path",
    "stress-command-code",
    "stress-destination-recipient",
    "stress-commitment-modality",
    "stress-negation",
]
EXPECTED_SYNTHETIC = {
    "synthetic-filler-removal": {
        "raw": "um I need the report",
        "expected": "I need the report",
        "tag": "filler-removal",
    },
    "synthetic-immediate-duplicate": {
        "raw": "send the report report now",
        "expected": "send the report now",
        "tag": "immediate-duplicate-removal",
    },
    "synthetic-explicit-correction": {
        "raw": "I need the old draft, no, the final draft",
        "expected": "I need the final draft",
        "tag": "explicit-correction",
    },
    "synthetic-punctuation-case": {
        "raw": "please send the report",
        "expected": "Please send the report.",
        "tag": "punctuation-case",
    },
    "synthetic-short-list": {
        "raw": "first privacy second speed",
        "expected": "1. Privacy\n2. Speed",
        "tag": "short-list-formatting",
    },
}


def validate_metadata(metadata, readme):
    require(metadata.get("schemaVersion") == 1, "metadata schemaVersion is not 1")
    candidate = metadata.get("candidate")
    require(isinstance(candidate, dict), "metadata candidate is missing")
    require(candidate.get("status") == "provisional", "candidate must be provisional")
    require(candidate.get("integrated") is False, "candidate must be unintegrated")
    require(candidate.get("admitted") is False, "candidate must be unadmitted")
    require(candidate.get("bundled") is False, "candidate must be unbundled")
    require(candidate.get("platform") == "Apple Silicon macOS", "candidate platform is not Apple Silicon macOS")
    require(candidate.get("languageScope") == "English only", "candidate language scope is not English only")
    require(candidate.get("registryPath") == "LLMRegistry.gemma3_1B_qat_4bit", "Gemma registry path changed")

    model = candidate.get("model")
    require(model == {
        "id": "mlx-community/gemma-3-1b-it-qat-4bit",
        "revision": EXPECTED_MODEL_REVISION,
        "format": "MLX",
        "quantization": "QAT 4-bit",
        "sourceURL": "https://huggingface.co/mlx-community/gemma-3-1b-it-qat-4bit",
    }, "model identity or format pin changed")

    upstream = candidate.get("upstream")
    require(upstream == {
        "id": "google/gemma-3-1b-it",
        "sourceURL": "https://huggingface.co/google/gemma-3-1b-it",
    }, "upstream Gemma identity changed")

    runtime = candidate.get("runtime")
    require(isinstance(runtime, dict), "runtime identity is missing")
    require(runtime.get("package") == "mlx-swift-lm", "runtime package changed")
    require(runtime.get("version") == "3.31.4", "runtime version changed")
    require(runtime.get("commit") == EXPECTED_MLX_SWIFT_LM_COMMIT, "runtime commit changed")
    require(runtime.get("sourceURL") == "https://github.com/ml-explore/mlx-swift-lm", "runtime source URL changed")
    require(runtime.get("packageSwiftSHA256") == "f03c532f6e128c04cc76fa5d92d05fd3bc1408ab9a883f86605bb9866725ffa2", "runtime Package.swift hash changed")
    require(runtime.get("mlxSwiftCompatibility") == {
        "dependencyDeclaration": ".package(url: \"https://github.com/ml-explore/mlx-swift\", .upToNextMinor(from: \"0.31.4\"))",
        "resolvedRange": ">=0.31.4,<0.32.0",
        "source": "Package.swift at mlx-swift-lm 3.31.4 commit",
    }, "MLX Swift compatibility requirement changed")

    license = metadata.get("license")
    require(isinstance(license, dict), "license metadata is missing")
    require(license.get("termsIdentity") == "Gemma Terms of Use", "Gemma terms identity changed")
    require(license.get("termsURL") == "https://ai.google.dev/gemma/terms", "Gemma terms URL changed")
    require(license.get("localUseStatement") == EXPECTED_LOCAL_USE_NOTICE, "local-use acceptance wording changed")
    require(license.get("redistributionStatement") == EXPECTED_REDISTRIBUTION_NOTICE, "redistribution obligation wording changed")
    require(license.get("distributionApprovalGranted") is False, "distribution approval must remain false")
    require(license.get("requiredDistributionObligations") == [
        "copy of the Gemma Terms of Use Agreement",
        "enforceable use restrictions",
        "required Notice file",
    ], "distribution obligations changed")

    inventory = metadata.get("artifactInventory")
    require(isinstance(inventory, dict), "artifact inventory is missing")
    require(inventory.get("repository") == "mlx-community/gemma-3-1b-it-qat-4bit", "artifact repository changed")
    require(inventory.get("revision") == EXPECTED_MODEL_REVISION, "artifact revision changed")
    require(inventory.get("sourceURL") == "https://huggingface.co/mlx-community/gemma-3-1b-it-qat-4bit/tree/15fed4eafb456c6fcb2a1165f19ac609670ed14b", "artifact source URL changed")
    require(inventory.get("files") == EXPECTED_MODEL_FILES, "artifact file inventory changed")
    require(inventory.get("weightsDownloaded") is False, "model weights must not be downloaded")
    require(inventory.get("runtimeDependenciesDownloaded") is False, "runtime dependencies must not be downloaded")
    require(inventory.get("contentAcquisition") == "metadata/tree/LFS pointer only; no model weight contents", "content acquisition boundary changed")

    for phrase in (
        "provisional",
        "unintegrated",
        "unadmitted",
        "unbundled",
        "zero semantic/protected/lexical violations",
        "FaithfulCleanupValidator",
    ):
        require(phrase in readme, f"README is missing required phrase: {phrase}")


def source_case_fields(case):
    return {
        key: case[key]
        for key in (
            "deterministicCleanupExpectedToChange",
            "id",
            "language",
            "protectedExpectations",
            "protectedForms",
            "rawBaseline",
            "sourceClass",
            "sourceEvidence",
            "tags",
        )
    }


def validate_corpus(corpus, source_corpus, source_bytes):
    require(corpus.get("schemaVersion") == 1, "corpus schemaVersion is not 1")
    require(corpus.get("corpusID") == "english-qualification-v1", "corpus ID changed")
    require(corpus.get("language") == "english", "corpus language must be English")
    require(corpus.get("sourceCorpus") == {
        "path": "Tools/QwenCleanupBenchmark/Qualification/corpus-v1.json",
        "corpusID": "fleck-qwen-cleanup-qualification-corpus-v1",
        "sha256": EXPECTED_SOURCE_CORPUS_SHA256,
    }, "source corpus identity changed")
    require(hashlib.sha256(source_bytes).hexdigest() == EXPECTED_SOURCE_CORPUS_SHA256, "accepted source corpus bytes changed")

    cases = corpus.get("cases")
    require(isinstance(cases, list), "corpus cases are missing")
    require(len(cases) == 38, f"expected 38 cases, got {len(cases)}")
    ids = [case.get("id") for case in cases]
    require(len(ids) == len(set(ids)), "corpus case IDs are not unique")
    require(ids[:12] == EXPECTED_QWEN_IDS, "Qwen English source case order/count changed")
    require(ids[12:24] == EXPECTED_WHISPER_IDS, "Whisper English source case order/count changed")
    require(ids[24:33] == EXPECTED_STRESS_IDS, "protected-stress source case order/count changed")
    require(ids[33:] == list(EXPECTED_SYNTHETIC), "synthetic utility case set changed")

    source_by_id = {case["id"]: case for case in source_corpus.get("cases", [])}
    for case in cases:
        require(case.get("language") == "english", f"non-English case is present: {case.get('id')}")
        require(not any("\u3400" <= character <= "\u9fff" for character in case.get("rawBaseline", "")), f"Han text is present: {case.get('id')}")
        require(case.get("evidenceClass") in {"publicHuman", "protectedStress", "syntheticUtility"}, f"invalid evidence class: {case.get('id')}")
        require(isinstance(case.get("source"), dict), f"source label is missing: {case.get('id')}")
        require(isinstance(case.get("protectedExpectations"), list), f"protected expectations are missing: {case.get('id')}")
        require(isinstance(case.get("protectedForms"), list), f"protected forms are missing: {case.get('id')}")

        if case["id"] in source_by_id:
            source_case = source_by_id[case["id"]]
            require(case.get("evidenceClass") == source_case["sourceClass"], f"evidence class changed: {case['id']}")
            require(case.get("source") == {
                "kind": "Qwen qualification corpus",
                "path": "Tools/QwenCleanupBenchmark/Qualification/corpus-v1.json",
                "caseID": case["id"],
            }, f"source label changed: {case['id']}")
            for key, expected in source_case_fields(source_case).items():
                require(case.get(key) == expected, f"source field changed: {case['id']}.{key}")
            require(case.get("sourceCaseSHA256") == canonical_sha256(source_case), f"source case hash changed: {case['id']}")
            require(case.get("expectedOutput") is None, f"source case has synthetic expected output: {case['id']}")
        else:
            expected = EXPECTED_SYNTHETIC.get(case["id"])
            require(expected is not None, f"unexpected synthetic case: {case.get('id')}")
            require(case.get("evidenceClass") == "syntheticUtility", f"synthetic evidence class changed: {case['id']}")
            require(case.get("source") == {
                "kind": "synthetic utility supplement",
                "caseID": case["id"],
            }, f"synthetic source label changed: {case['id']}")
            require(case.get("rawBaseline") == expected["raw"], f"synthetic raw utility changed: {case['id']}")
            require(case.get("expectedOutput") == expected["expected"], f"synthetic output expectation changed: {case['id']}")
            require(case.get("deterministicCleanupExpectedToChange") is True, f"synthetic change expectation changed: {case['id']}")
            require(case.get("tags") == ["synthetic", "utility", expected["tag"]], f"synthetic tags changed: {case['id']}")
            require(case.get("protectedForms") == [], f"synthetic protected forms changed: {case['id']}")
            require(case.get("protectedExpectations") == [], f"synthetic protected expectations changed: {case['id']}")
            require("sourceCaseSHA256" not in case, f"synthetic case has a source hash: {case['id']}")

    expected_counts = corpus.get("expectedCounts")
    require(expected_counts == {
        "total": 38,
        "publicHuman": 24,
        "publicHumanByEngine": {"qwen": 12, "whisper": 12},
        "protectedStress": 9,
        "syntheticUtility": 5,
    }, "corpus expected counts changed")


def validate(metadata, corpus, source_corpus, source_bytes, readme):
    validate_metadata(metadata, readme)
    validate_corpus(corpus, source_corpus, source_bytes)


def expect_rejection(label, mutate, metadata, corpus, source_corpus, source_bytes, readme):
    mutated_metadata = copy.deepcopy(metadata)
    mutated_corpus = copy.deepcopy(corpus)
    mutate(mutated_metadata, mutated_corpus)
    try:
        validate(mutated_metadata, mutated_corpus, source_corpus, source_bytes, readme)
    except ContractError:
        return
    fail(f"fixture mutation was accepted: {label}")


metadata_path, corpus_path, source_path, readme_path = map(Path, sys.argv[1:])
try:
    metadata = load_json(metadata_path)
    corpus = load_json(corpus_path)
    source_corpus = load_json(source_path)
    source_bytes = source_path.read_bytes()
    readme = readme_path.read_text(encoding="utf-8")
    validate(metadata, corpus, source_corpus, source_bytes, readme)

    expect_rejection("model revision", lambda meta, _: meta["candidate"]["model"].__setitem__("revision", "0" * 40), metadata, corpus, source_corpus, source_bytes, readme)
    expect_rejection("license Notice obligation", lambda meta, _: meta["license"].__setitem__("redistributionStatement", "No distribution approval is granted."), metadata, corpus, source_corpus, source_bytes, readme)
    expect_rejection("source baseline", lambda _, corp: corp["cases"][0].__setitem__("rawBaseline", "mutated"), metadata, corpus, source_corpus, source_bytes, readme)
    expect_rejection("source case hash", lambda _, corp: corp["cases"][0].__setitem__("sourceCaseSHA256", "0" * 64), metadata, corpus, source_corpus, source_bytes, readme)
    expect_rejection("Mandarin or mixed case", lambda _, corp: corp["cases"][0].__setitem__("language", "mixed"), metadata, corpus, source_corpus, source_bytes, readme)
except ContractError as error:
    print(f"gemma-metadata-corpus-contract: FAIL {error}", file=sys.stderr)
    raise SystemExit(1)

print(
    "gemma-metadata-corpus-contract: PASS "
    "totalCases=38 sourceCases=33 syntheticUtilityCases=5 "
    "qwenEnglish=12 whisperEnglish=12 protectedStress=9 fixtureMutationsRejected=5"
)
PY
