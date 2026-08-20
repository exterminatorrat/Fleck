#!/usr/bin/env bash

set -euo pipefail

readonly test_dir="$(cd "$(dirname "$0")" && pwd)"
readonly corpus_dir="$test_dir/../Corpus"
readonly schema="$corpus_dir/schema-v1.json"
readonly manifest="$corpus_dir/manifest-v1.json"
readonly acquire="$corpus_dir/acquire-corpus.sh"
readonly generator="$corpus_dir/generate-nonspeech.swift"
readonly repository_root="$(cd "$test_dir/../../../.." && pwd)"

for required_path in "$schema" "$manifest" "$acquire" "$generator"; do
  if [[ ! -f "$required_path" ]]; then
    echo "missing corpus contract behavior: $required_path" >&2
    exit 1
  fi
done

python3 - "$schema" "$manifest" <<'PY'
import json
import re
import sys
from collections import Counter

schema_path, manifest_path = sys.argv[1:]
with open(schema_path, encoding="utf-8") as handle:
    schema = json.load(handle)
with open(manifest_path, encoding="utf-8") as handle:
    manifest = json.load(handle)


def resolve(root, reference):
    assert reference.startswith("#/"), f"unsupported reference: {reference}"
    value = root
    for part in reference[2:].split("/"):
        value = value[part.replace("~1", "/").replace("~0", "~")]
    return value


def validate(value, contract, path="instance", root=schema):
    if "$ref" in contract:
        validate(value, resolve(root, contract["$ref"]), path, root)
        return
    for child in contract.get("allOf", []):
        validate(value, child, path, root)
    if "if" in contract:
        condition_holds = True
        try:
            validate(value, contract["if"], path, root)
        except AssertionError:
            condition_holds = False
        selected = contract.get("then" if condition_holds else "else")
        if selected is not None:
            validate(value, selected, path, root)
    if "not" in contract:
        try:
            validate(value, contract["not"], path, root)
        except AssertionError:
            pass
        else:
            raise AssertionError(f"{path}: must not match schema")
    if "const" in contract:
        assert value == contract["const"], f"{path}: expected const {contract['const']!r}"
    if "enum" in contract:
        assert value in contract["enum"], f"{path}: unexpected enum value {value!r}"
    if "type" in contract:
        types = contract["type"] if isinstance(contract["type"], list) else [contract["type"]]
        matches = any(
            (kind == "object" and isinstance(value, dict))
            or (kind == "array" and isinstance(value, list))
            or (kind == "string" and isinstance(value, str))
            or (kind == "integer" and isinstance(value, int) and not isinstance(value, bool))
            or (kind == "number" and isinstance(value, (int, float)) and not isinstance(value, bool))
            or (kind == "boolean" and isinstance(value, bool))
            or (kind == "null" and value is None)
            for kind in types
        )
        assert matches, f"{path}: type mismatch"
    if isinstance(value, dict):
        for key in contract.get("required", []):
            assert key in value, f"{path}: missing {key}"
        properties = contract.get("properties", {})
        if contract.get("additionalProperties") is False:
            assert set(value) <= set(properties), f"{path}: unknown keys {set(value) - set(properties)}"
        for key, child in properties.items():
            if key in value:
                validate(value[key], child, f"{path}.{key}", root)
    if isinstance(value, list) and "items" in contract:
        for index, item in enumerate(value):
            validate(item, contract["items"], f"{path}[{index}]", root)
    if isinstance(value, list) and "minItems" in contract:
        assert len(value) >= contract["minItems"], f"{path}: too short"
    if isinstance(value, list) and "maxItems" in contract:
        assert len(value) <= contract["maxItems"], f"{path}: too long"
    if isinstance(value, str):
        if "minLength" in contract:
            assert len(value) >= contract["minLength"], f"{path}: too short"
        if "pattern" in contract:
            assert re.search(contract["pattern"], value), f"{path}: pattern mismatch"
    if isinstance(value, (int, float)) and not isinstance(value, bool) and "minimum" in contract:
        assert value >= contract["minimum"], f"{path}: below minimum"


def assert_object_schemas_are_closed(node, path="schema"):
    if isinstance(node, dict):
        if node.get("type") == "object":
            assert node.get("additionalProperties") is False, f"{path}: object is not closed"
        for key, child in node.items():
            assert_object_schemas_are_closed(child, f"{path}.{key}")
    elif isinstance(node, list):
        for index, child in enumerate(node):
            assert_object_schemas_are_closed(child, f"{path}[{index}]")


assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
assert_object_schemas_are_closed(schema)
validate(manifest, schema)

revision = "a3c817cbf7c08863e0c472861c7c39e27ce7f38e"
source = manifest["source"]
assert manifest["schemaVersion"] == 1
assert manifest["immutable"] is True
assert source["dataset"] == "google/fleurs"
assert source["revision"] == revision
assert source["license"] == "CC-BY-4.0"
assert source["licenseURL"] == "https://creativecommons.org/licenses/by/4.0/"
expected_files = {
    "englishValidation": {
        "path": "en_us/validation-00000-of-00001.parquet",
        "sha256": "7c3eebdff31e1c510b78e51319e5b9779429b87c9895f2e5f3005bfe68854c65",
        "byteCount": 236549523,
    },
    "mandarinValidation": {
        "path": "cmn_hans_cn/validation-00000-of-00001.parquet",
        "sha256": "18698f80879a221f68318a4ccb8752b74c2f5bf521af0e0011b07e4670ea62ad",
        "byteCount": 287985961,
    },
}
for key, expected in expected_files.items():
    observed = source["files"][key]
    assert observed["path"] == expected["path"]
    assert observed["sha256"] == expected["sha256"]
    assert observed["byteCount"] == expected["byteCount"]
    assert observed["url"] == f"https://huggingface.co/datasets/google/fleurs/resolve/{revision}/{expected['path']}"

cases = manifest["cases"]
expected_composite_spans = {
    "mixed-01": [
        {"endSample": 203520, "language": "en_us", "reference": "108 plates of Chhappan Bhog (in Hinduism, 56 different edible items, like, sweets, fruits, nuts, dishes etc. which are offered to deity) were served to Baba Shyam.", "sourceCaseID": "en_us-01", "startSample": 0},
        {"endSample": 392960, "language": "cmn_hans_cn", "reference": "咖喱饭菜既可以是“干”的，也可以是“湿”的，干湿情况取决于水量多少。", "sourceCaseID": "cmn_hans_cn-01", "startSample": 211520},
    ],
    "mixed-02": [
        {"endSample": 145920, "language": "cmn_hans_cn", "reference": "滑雪是许多滑雪爱好者的主要旅游活动，这些爱好者有时也被称为“滑雪狂人”，他们计划整个假期都在某个地点滑雪。", "sourceCaseID": "cmn_hans_cn-02", "startSample": 0},
        {"endSample": 317120, "language": "en_us", "reference": "Many common formats (APS family of formats, for example) are equal to or closely approximate this aspect ratio.", "sourceCaseID": "en_us-02", "startSample": 153920},
    ],
    "mixed-03": [
        {"endSample": 110400, "language": "en_us", "reference": "The largest tournament of the year takes place in December at the polo fields in Las Cañitas.", "sourceCaseID": "en_us-03", "startSample": 0},
        {"endSample": 204800, "language": "cmn_hans_cn", "reference": "这成了普遍做法，但铁片会使木制的马车轮子磨损更严重。", "sourceCaseID": "cmn_hans_cn-03", "startSample": 118400},
    ],
    "mixed-04": [
        {"endSample": 79680, "language": "cmn_hans_cn", "reference": "然后，拉卡·辛格带头唱了拜赞歌。", "sourceCaseID": "cmn_hans_cn-04", "startSample": 0},
        {"endSample": 211520, "language": "en_us", "reference": "The Report opens with plea for open debate and the formation of a consensus in the United States about the policy towards the Middle East.", "sourceCaseID": "en_us-04", "startSample": 87680},
    ],
    "mixed-05": [
        {"endSample": 109440, "language": "en_us", "reference": "The Arabs also brought Islam to the lands, and it took in a big way in the Comoros and Mayotte.", "sourceCaseID": "en_us-05", "startSample": 0},
        {"endSample": 302400, "language": "cmn_hans_cn", "reference": "亚马逊河也是地球上最宽的河流，有些河段的宽度可达6英里。", "sourceCaseID": "cmn_hans_cn-05", "startSample": 117440},
    ],
    "mixed-06": [
        {"endSample": 144960, "language": "cmn_hans_cn", "reference": "据报道，由于执法人员不在场，比什凯克街道上的大规模抢劫持续了一夜。", "sourceCaseID": "cmn_hans_cn-06", "startSample": 0},
        {"endSample": 433600, "language": "en_us", "reference": "She came to this conclusion due to the multitude of positive comments and encouragement sent to her by both female and male individuals urging that contraception medication be considered a medical necessity.", "sourceCaseID": "en_us-06", "startSample": 152960},
    ],
    "mixed-07": [
        {"endSample": 165120, "language": "en_us", "reference": "Air accidents are common in Iran, which has an aging fleet that is poorly maintained both for civil and military operations.", "sourceCaseID": "en_us-07", "startSample": 0},
        {"endSample": 344000, "language": "cmn_hans_cn", "reference": "藏传佛教以佛陀的教义为基础，但通过大乘佛教的普世之爱和印度瑜伽的许多技巧得到了拓展。", "sourceCaseID": "cmn_hans_cn-07", "startSample": 173120},
    ],
    "mixed-08": [
        {"endSample": 184320, "language": "cmn_hans_cn", "reference": "罗宾·乌萨帕 (Robin Uthappa) 取得了本局的最高分，投出了 11 个四分球和 2 个六分球，仅投出 41 个球便赢得 70 分。", "sourceCaseID": "cmn_hans_cn-08", "startSample": 0},
        {"endSample": 352320, "language": "en_us", "reference": "Robin Uthappa made the innings highest score, 70 runs in just 41 balls by hitting 11 fours and 2 sixes.", "sourceCaseID": "en_us-08", "startSample": 192320},
    ],
    "mixed-09": [
        {"endSample": 170880, "language": "en_us", "reference": "Ancient Roman meals couldn't have included foods that came to Europe from America or from Asia in later centuries.", "sourceCaseID": "en_us-09", "startSample": 0},
        {"endSample": 352640, "language": "cmn_hans_cn", "reference": "如今，科学表明，这种大规模的碳经济，再也无法让过去 200 万年来支持人类进化发展的生物圈保持稳定状态。", "sourceCaseID": "cmn_hans_cn-09", "startSample": 178880},
    ],
    "mixed-10": [
        {"endSample": 99840, "language": "cmn_hans_cn", "reference": "美国总统乔治·沃克·布什对这一公告表示支持。", "sourceCaseID": "cmn_hans_cn-10", "startSample": 0},
        {"endSample": 246080, "language": "en_us", "reference": "Arly Velasquez of Mexico finished fifteenth in the men's sitting Super-G. New Zealand's Adam Hall finished ninth in the men's standing Super-G.", "sourceCaseID": "en_us-10", "startSample": 107840},
    ],
    "mixed-11": [
        {"endSample": 86400, "language": "en_us", "reference": "The Spaniards started the colonization period which lasted for three centuries.", "sourceCaseID": "en_us-11", "startSample": 0},
        {"endSample": 196160, "language": "cmn_hans_cn", "reference": "全国各地的著名歌手都唱祈祷歌献给 Shri Shyam。", "sourceCaseID": "cmn_hans_cn-11", "startSample": 94400},
    ],
    "mixed-12": [
        {"endSample": 163200, "language": "cmn_hans_cn", "reference": "学生往往是最挑剔的读者，所以博客作者开始努力提高写作水平，避免受到批判。", "sourceCaseID": "cmn_hans_cn-12", "startSample": 0},
        {"endSample": 368960, "language": "en_us", "reference": "The park covers 19,500 km² and is divided in 14 different ecozones, each supporting different wildlife.", "sourceCaseID": "en_us-12", "startSample": 171200},
    ],
}
assert len(cases) == 41
assert len({item["id"] for item in cases}) == len(cases)
assert Counter((item["language"], item["sourceClass"]) for item in cases) == Counter({
    ("english", "publicHuman"): 12,
    ("mandarin", "publicHuman"): 12,
    ("mixed", "publicHumanComposite"): 12,
    ("none", "synthetic"): 5,
})
for item in cases:
    assert item["sourceClass"] != "operatorLiveHuman"
    assert item["naturalCodeSwitch"] is False
    assert re.fullmatch(r"[0-9a-f]{64}", item["audioSHA256"])
    assert item["audioDurationMilliseconds"] >= 0
    if item["sourceClass"] == "publicHumanComposite":
        assert item["codeSwitchSpans"] == expected_composite_spans[item["id"]]
        assert len(item["codeSwitchSpans"]) == 2
        assert all(list(span) == ["endSample", "language", "reference", "sourceCaseID", "startSample"] for span in item["codeSwitchSpans"])
        for span in item["codeSwitchSpans"]:
            assert span["startSample"] < span["endSample"]
    else:
        assert "codeSwitchSpans" not in item
print("contract=manifest-schema-pins-counts:pass")
print("contract=composite-spans-exact-and-ordered:pass")
PY

forbidden_paths="$(git -C "$repository_root" ls-files | rg -i '\.(wav|wave|mp3|m4a|flac|ogg|parquet|zip|tar|tgz|gz|7z)$' || true)"
if [[ -n "$forbidden_paths" ]]; then
  echo "tracked audio/parquet/archive files are forbidden:" >&2
  printf '%s\n' "$forbidden_paths" >&2
  exit 1
fi
echo "contract=no-tracked-audio-parquet-archive:pass"

readonly test_tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/fleck-corpus-contract.XXXXXX")"
trap 'rm -rf "$test_tmp_root"' EXIT
readonly generator_binary="$test_tmp_root/generate-nonspeech"
mkdir "$test_tmp_root/module-cache"
CLANG_MODULE_CACHE_PATH="$test_tmp_root/module-cache" swiftc -O -parse-as-library "$generator" -o "$generator_binary"

mkdir "$test_tmp_root/nonspeech-a" "$test_tmp_root/nonspeech-b"
"$generator_binary" "$test_tmp_root/nonspeech-a"
"$generator_binary" "$test_tmp_root/nonspeech-b"

readonly expected_inventory=$'alternating-silence-noise-10s.wav\nimpulse-train-5s.wav\nsilence-5s.wav\nwhite-noise-low-5s.wav\nwhite-noise-medium-5s.wav'
readonly first_inventory="$(find "$test_tmp_root/nonspeech-a" -mindepth 1 -maxdepth 1 -type f -name '*.wav' -exec basename {} \; | sort)"
readonly second_inventory="$(find "$test_tmp_root/nonspeech-b" -mindepth 1 -maxdepth 1 -type f -name '*.wav' -exec basename {} \; | sort)"
[[ "$first_inventory" == "$expected_inventory" ]]
[[ "$second_inventory" == "$expected_inventory" ]]

python3 - "$manifest" "$test_tmp_root/nonspeech-a" "$test_tmp_root/nonspeech-b" <<'PY'
import hashlib
import json
import os
import struct
import sys

manifest_path, *roots = sys.argv[1:]
with open(manifest_path, encoding="utf-8") as handle:
    expected = {
        case["sourceFile"]: case
        for case in json.load(handle)["cases"]
        if case["sourceClass"] == "synthetic"
    }

for root in roots:
    for filename, case in expected.items():
        path = os.path.join(root, filename)
        with open(path, "rb") as handle:
            data = handle.read()
        assert len(data) == case["audioBytes"], filename
        assert hashlib.sha256(data).hexdigest() == case["audioSHA256"], filename
        assert data[:4] == b"RIFF" and data[8:12] == b"WAVE"
        chunk, chunk_size = struct.unpack_from("<4sI", data, 12)
        assert (chunk, chunk_size) == (b"fmt ", 18)
        audio_format, channels, sample_rate, byte_rate, block_align, bits, extra = struct.unpack_from("<HHIIHHH", data, 20)
        assert (audio_format, channels, sample_rate, byte_rate, block_align, bits, extra) == (3, 1, 16000, 64000, 4, 32, 0)
        fact, fact_size, sample_count = struct.unpack_from("<4sII", data, 38)
        assert (fact, fact_size, sample_count) == (b"fact", 4, case["audioDurationMilliseconds"] * 16)
        data_tag, data_size = struct.unpack_from("<4sI", data, 50)
        assert (data_tag, data_size) == (b"data", len(data) - 58)
    print(f"generator=exact-hashes-and-shape:{os.path.basename(root)}:pass")
PY

if "$generator_binary" "$test_tmp_root/nonspeech-a" >/dev/null 2>&1; then
  echo "generator overwrote a non-empty destination" >&2
  exit 1
fi
mkdir "$test_tmp_root/generator-link-target"
ln -s "$test_tmp_root/generator-link-target" "$test_tmp_root/generator-link"
if "$generator_binary" "$test_tmp_root/generator-link" >/dev/null 2>&1; then
  echo "generator followed a symlinked destination" >&2
  exit 1
fi
if "$generator_binary" relative-destination >/dev/null 2>&1; then
  echo "generator accepted a relative destination" >&2
  exit 1
fi
echo "generator=safety-refusals:pass"

sh -n "$acquire"
readonly fake_bin="$test_tmp_root/fake-bin"
readonly curl_marker="$test_tmp_root/curl-was-called"
mkdir "$fake_bin" "$test_tmp_root/acquire-destination"
printf '#!/bin/sh\n: > %q\nexit 97\n' "$curl_marker" > "$fake_bin/curl"
chmod +x "$fake_bin/curl"
readonly dry_run_output="$(PATH="$fake_bin:$PATH" "$acquire" --dry-run "$test_tmp_root/acquire-destination")"
[[ "$dry_run_output" == *"dry-run"* ]]
[[ ! -e "$curl_marker" ]]
[[ -z "$(find "$test_tmp_root/acquire-destination" -mindepth 1 -maxdepth 1 -print -quit)" ]]
if "$acquire" --dry-run relative-destination >/dev/null 2>&1; then
  echo "acquire accepted a relative destination" >&2
  exit 1
fi
ln -s "$test_tmp_root/generator-link-target" "$test_tmp_root/acquire-symlink"
if "$acquire" --dry-run "$test_tmp_root/acquire-symlink" >/dev/null 2>&1; then
  echo "acquire accepted a symlinked destination" >&2
  exit 1
fi
mkdir "$test_tmp_root/acquire-overwrite"
touch "$test_tmp_root/acquire-overwrite/en_us-validation-00000-of-00001.parquet"
if "$acquire" --dry-run "$test_tmp_root/acquire-overwrite" >/dev/null 2>&1; then
  echo "acquire accepted an output-overwrite target" >&2
  exit 1
fi
echo "acquire=syntax-dry-run-and-safety:pass"
if ! grep -Fq '/bin/link "$partial" "$final"' "$acquire"; then
  echo "acquire does not use the exclusive macOS link primitive" >&2
  exit 1
fi

for competitor in regular directory symlink-directory; do
  publication_root="$test_tmp_root/publication-$competitor"
  mkdir "$publication_root"
  publication_partial="$publication_root/output.parquet.partial"
  publication_final="$publication_root/output.parquet"
  printf partial-content > "$publication_partial"
  case "$competitor" in
    regular) printf regular-marker > "$publication_final" ;;
    directory) mkdir "$publication_final"; printf directory-marker > "$publication_final/marker" ;;
    symlink-directory) mkdir "$publication_root/target"; printf symlink-marker > "$publication_root/target/marker"; ln -s "$publication_root/target" "$publication_final" ;;
  esac
  if /bin/link "$publication_partial" "$publication_final" >/dev/null 2>&1; then
    echo "exclusive publication accepted a competing $competitor target" >&2
    exit 1
  fi
  [[ -e "$publication_partial" && ! -L "$publication_partial" ]]
  [[ -e "$publication_final" || -L "$publication_final" ]]
  case "$competitor" in
    regular) [[ -f "$publication_final" && ! -L "$publication_final" && "$(cat "$publication_final")" == regular-marker ]] ;;
    directory) [[ -d "$publication_final" && ! -L "$publication_final" && "$(cat "$publication_final/marker")" == directory-marker ]] ;;
    symlink-directory) [[ -L "$publication_final" && "$(cat "$publication_final/marker")" == symlink-marker ]] ;;
  esac
  stray_link="$publication_final/$(basename "$publication_partial")"
  [[ ! -e "$stray_link" && ! -L "$stray_link" ]]
  echo "acquire=publication-target-safety:$competitor:pass"
done

readonly resume_bin="$test_tmp_root/resume-bin"
mkdir "$resume_bin"
printf '%s\n' \
  '#!/bin/sh' \
  'set -eu' \
  'printf "stat %s\\n" "$3" >> "${CORPUS_TEST_VERIFY_LOG:-/dev/null}"' \
  'case "$3" in' \
  '  *en_us*)' \
  '    if [ "${CORPUS_TEST_MODE:-}" = wrong-bytes ]; then printf "4\\n"; else printf "236549523\\n"; fi ;;' \
  '  *cmn_hans_cn*)' \
  '    if [ -e "${CORPUS_TEST_STATE:-/nonexistent}/resumed" ]; then printf "287985961\\n"; else printf "7\\n"; fi ;;' \
  '  *) exit 99 ;;' \
  'esac' > "$resume_bin/stat"
printf '%s\n' \
  '#!/bin/sh' \
  'set -eu' \
  'printf "shasum %s\\n" "$3" >> "${CORPUS_TEST_VERIFY_LOG:-/dev/null}"' \
  'case "$3" in' \
  '  *en_us*)' \
  '    if [ "${CORPUS_TEST_MODE:-}" = wrong-hash ]; then printf "0000000000000000000000000000000000000000000000000000000000000000  %s\\n" "$3"; else printf "7c3eebdff31e1c510b78e51319e5b9779429b87c9895f2e5f3005bfe68854c65  %s\\n" "$3"; fi ;;' \
  '  *cmn_hans_cn*) printf "18698f80879a221f68318a4ccb8752b74c2f5bf521af0e0011b07e4670ea62ad  %s\\n" "$3" ;;' \
  '  *) exit 99 ;;' \
  'esac' > "$resume_bin/shasum"
printf '%s\n' \
  '#!/bin/sh' \
  'set -eu' \
  'output=' \
  'expect_output=false' \
  'for argument in "$@"; do' \
  '  if [ "$expect_output" = true ]; then output="$argument"; expect_output=false;' \
  '  elif [ "$argument" = "--output" ]; then expect_output=true;' \
  '  fi' \
  'done' \
  'printf "%s\\n" "$*" >> "${CORPUS_TEST_CURL_LOG:?}"' \
  'case "$output" in' \
  '  *en_us*) : > "${CORPUS_TEST_ENGLISH_CURL_MARKER:?}"; exit 97 ;;' \
  '  *cmn_hans_cn*) printf resumed-mandarin > "$output"; : > "${CORPUS_TEST_STATE:?}/resumed" ;;' \
  '  *) exit 98 ;;' \
  'esac' > "$resume_bin/curl"
chmod +x "$resume_bin/stat" "$resume_bin/shasum" "$resume_bin/curl"

resume_state="$test_tmp_root/resume-state"
resume_destination="$test_tmp_root/interrupted-retry"
resume_curl_log="$test_tmp_root/interrupted-retry-curl.log"
resume_english_curl="$test_tmp_root/interrupted-retry-english-curl"
resume_output="$test_tmp_root/interrupted-retry-output"
resume_sentinel="$test_tmp_root/interrupted-retry-sentinel"
resume_verify_log="$test_tmp_root/interrupted-retry-verify.log"
mkdir "$resume_state" "$resume_destination"
printf verified-english > "$resume_destination/en_us-validation-00000-of-00001.parquet"
printf partial > "$resume_destination/cmn_hans_cn-validation-00000-of-00001.parquet.partial"
printf sentinel > "$resume_sentinel"
if ! CORPUS_TEST_MODE=resume CORPUS_TEST_STATE="$resume_state" CORPUS_TEST_CURL_LOG="$resume_curl_log" CORPUS_TEST_ENGLISH_CURL_MARKER="$resume_english_curl" CORPUS_TEST_VERIFY_LOG="$resume_verify_log" PATH="$resume_bin:$PATH" "$acquire" "$resume_destination" > "$resume_output" 2>&1; then
  cat "$resume_output" >&2
  echo "acquire did not resume the interrupted second download" >&2
  exit 1
fi
[[ ! -e "$resume_english_curl" ]]
english_stat_verifications="$(grep -F -c "stat $resume_destination/en_us-validation-00000-of-00001.parquet" "$resume_verify_log" || true)"
english_hash_verifications="$(grep -F -c "shasum $resume_destination/en_us-validation-00000-of-00001.parquet" "$resume_verify_log" || true)"
[[ "$english_stat_verifications" -ge 2 ]]
[[ "$english_hash_verifications" -ge 2 ]]
[[ -e "$resume_curl_log" ]]
! grep -Fq en_us "$resume_curl_log"
grep -Fq -- '--continue-at - --output' "$resume_curl_log"
grep -Fq cmn_hans_cn "$resume_curl_log"
[[ "$(cat "$resume_destination/en_us-validation-00000-of-00001.parquet")" == verified-english ]]
[[ "$(cat "$resume_destination/cmn_hans_cn-validation-00000-of-00001.parquet")" == resumed-mandarin ]]
[[ ! -e "$resume_destination/cmn_hans_cn-validation-00000-of-00001.parquet.partial" ]]
[[ "$(cat "$resume_sentinel")" == sentinel ]]
echo "acquire=interrupted-second-download-resume:pass"

for invalid_mode in wrong-bytes wrong-hash; do
  invalid_destination="$test_tmp_root/final-$invalid_mode"
  invalid_state="$test_tmp_root/final-$invalid_mode-state"
  invalid_curl_log="$test_tmp_root/final-$invalid_mode-curl.log"
  invalid_english_curl="$test_tmp_root/final-$invalid_mode-english-curl"
  mkdir "$invalid_destination" "$invalid_state"
  printf original-final > "$invalid_destination/en_us-validation-00000-of-00001.parquet"
  if CORPUS_TEST_MODE="$invalid_mode" CORPUS_TEST_STATE="$invalid_state" CORPUS_TEST_CURL_LOG="$invalid_curl_log" CORPUS_TEST_ENGLISH_CURL_MARKER="$invalid_english_curl" PATH="$resume_bin:$PATH" "$acquire" "$invalid_destination" >/dev/null 2>&1; then
    echo "acquire accepted an invalid $invalid_mode final" >&2
    exit 1
  fi
  [[ "$(cat "$invalid_destination/en_us-validation-00000-of-00001.parquet")" == original-final ]]
  [[ ! -e "$invalid_curl_log" && ! -e "$invalid_english_curl" ]]
  echo "acquire=invalid-final-$invalid_mode:pass"
done

for invalid_final_type in directory symlink; do
  invalid_destination="$test_tmp_root/final-$invalid_final_type"
  invalid_state="$test_tmp_root/final-$invalid_final_type-state"
  invalid_curl_log="$test_tmp_root/final-$invalid_final_type-curl.log"
  invalid_english_curl="$test_tmp_root/final-$invalid_final_type-english-curl"
  mkdir "$invalid_destination" "$invalid_state"
  case "$invalid_final_type" in
    directory) mkdir "$invalid_destination/en_us-validation-00000-of-00001.parquet"; printf directory-marker > "$invalid_destination/en_us-validation-00000-of-00001.parquet/marker" ;;
    symlink) mkdir "$invalid_destination/target"; printf symlink-marker > "$invalid_destination/target/marker"; ln -s "$invalid_destination/target" "$invalid_destination/en_us-validation-00000-of-00001.parquet" ;;
  esac
  if CORPUS_TEST_MODE=resume CORPUS_TEST_STATE="$invalid_state" CORPUS_TEST_CURL_LOG="$invalid_curl_log" CORPUS_TEST_ENGLISH_CURL_MARKER="$invalid_english_curl" PATH="$resume_bin:$PATH" "$acquire" "$invalid_destination" >/dev/null 2>&1; then
    echo "acquire accepted an expected-name $invalid_final_type" >&2
    exit 1
  fi
  case "$invalid_final_type" in
    directory) [[ "$(cat "$invalid_destination/en_us-validation-00000-of-00001.parquet/marker")" == directory-marker ]] ;;
    symlink) [[ -L "$invalid_destination/en_us-validation-00000-of-00001.parquet" && "$(cat "$invalid_destination/en_us-validation-00000-of-00001.parquet/marker")" == symlink-marker ]] ;;
  esac
  [[ ! -e "$invalid_curl_log" && ! -e "$invalid_english_curl" ]]
  echo "acquire=invalid-final-$invalid_final_type:pass"
done

echo "corpus contract tests: PASS"
