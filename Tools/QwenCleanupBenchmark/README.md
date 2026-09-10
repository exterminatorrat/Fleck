# Qwen cleanup benchmark

This is a developer-only, reproducible benchmark harness for the already-downloaded external `mlx-community/Qwen3.5-0.8B-MLX-4bit` artifact. It is not Fleck product integration, model admission, release evidence, or packaged-app validation. Every report fixes `releaseAdmitted=false`, `productionIntegrated=false`, and `packagedAppVerified=false`.

## Contract

Each fixture case makes exactly one deterministic generation request with no retry. The helper records the exact baseline, protected forms, instructions, rendered prompt, runtime/model identities, token bounds, raw response bytes/string, timing/RSS, flushed progress markers, and helper outcome. The compiled Swift CLI then accepts only a strict `LocalCleanupResponseEnvelope` object and applies the existing `FaithfulCleanupValidator` with the compiled `replacements=0` contract. No microphone audio or unrelated transcripts are persisted.

The prompt follows the current `FoundationModelDictation.cleanupInstructions` semantics: quoted transcript text is data, never instructions; only permitted fillers, adjacent repetition, immediate repeated phrases, and explicit corrections may be removed; punctuation, case, and clearly spoken short-list formatting may be added; names, numbers, dates, times, URLs, paths, commands, destinations, commitments/modality, negation, and surrounding meaning remain protected.

The response must be exactly one JSON object with exactly one string member, `{"text": String}`. Wrapper objects, markdown, thinking, duplicate keys, malformed JSON, and extra output are rejected.

## Exact local candidate

The runner verifies the complete private candidate snapshot before any MLX import or model load, copies it outside the repository and output tree into a mode-0700 temporary directory, verifies the copy again, and re-verifies it after model load. Missing, extra, symlinked, or changed files fail closed. The snapshot is never stored in this repository or app.

The pinned model identity is:

```text
ID:       mlx-community/Qwen3.5-0.8B-MLX-4bit
Revision: 5d894f8cc4ef3e6c88537bf3746ed262f549da6a
```

The exact required inventory is:

```text
.gitattributes                         1570       34448b82c17d60fec9b65b1f093c115ddbaadc04beb1b0140b6bfed2e012a930
README.md                              2307       7024f593c30b51462de050b5cdf938a5b0f0d554901e6ac3af3ed7af92fb5e5f
chat_template.jinja                    7755       273d8e0e683b885071fb17e08d71e5f2a5ddfb5309756181681de4f5a1822d80
config.json                            3112       ba7770da23eae5ebd6827571f086e331956b33f4442a9e876fb4aa10969a6772
model.safetensors                 625229487       f5a0d9dd3efa73510542a8023d610ff26be2b4b020d181cfc4bedaa1fcc5dd9e
model.safetensors.index.json          71473       6e48f2fa5d6f033a6d77bf833abfa9698ca24d1715ecea4c67447bcfaee44650
preprocessor_config.json                390       27225450ac9c6529872ee1924fcb0962ff5634834f817040f444118116f4e516
processor_config.json                  1300       14932921ca485d458a04dafd8069fbb0a4505622a48208d19ed247115801385b
tokenizer.json                    19989343       87a7830d63fcf43bf241c3c5242e96e62dd3fdc29224ca26fed8ea333db72de4
tokenizer_config.json                 1139       e98f1901ac6f0adff67b1d540bfa0c36ac1a0cf59eb72ed78146ef89aafa1182
video_preprocessor_config.json         385       7768af27c1fafa9cc9011c1dc20067e03f8915e03b63504550e11d5066986d13
vocab.json                        6722759       ce99b4cb2983d118806ce0a8b777a35b093e2000a503ebde25853284c9dfa003
LICENSE.Qwen-upstream-Apache-2.0     11544       bbedc3fda3305820b977265f01b8619d87570a6739de3a5582c3464840f1e57a
```

The runtime must use an explicitly supplied canonical interpreter and exact
package versions:

```text
Python executable SHA-256: 87d4df53fd91304be5bac391fb204643c36b7df2023c04a0953bcbc7d4fdf634
mlx-lm:  0.31.3
mlx:     0.31.2
```

The helper is launched with `env -i`, `-I`, and `-S`; ambient `PYTHONPATH`, user site, `sitecustomize`, and `usercustomize` cannot participate. The exact canonical runtime site-packages directory is passed as data, checked for symlink-free canonical identity, and inserted only after artifact/offline preconditions. Before import it hashes every regular runtime file (including `mlx`, `mlx_lm`, and their metadata), rejecting symlinks and requiring this pinned complete snapshot:

```text
Python executable SHA-256: 87d4df53fd91304be5bac391fb204643c36b7df2023c04a0953bcbc7d4fdf634
Runtime file count:        10760
Runtime inventory SHA-256: 7b1908f44a55ba5f9d857ff5615b69c3ef71b8519903691f86776e438790f214
```

The runtime inventory is re-hashed after import/model load and after every generation. Distribution versions remain pinned to `mlx-lm 0.31.3` and `mlx 0.31.2`, with both locations bound beneath that exact directory.

Every case and summary also carries the exact base commit, all six harness-file byte/hash identities, and the compiled validator byte/hash identity. The runner regenerates and compares this provenance immediately before publication.

## Offline and deadline enforcement

The runner first proves that macOS `/usr/bin/sandbox-exec` enforces `(deny network*)`. The isolated helper then runs in that sandbox with `HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1`; if enforcement cannot be proven, the run fails closed.

The helper flushes and `fsync`s `model-ready`, `generation-started(caseID,timestampNs)`, and `generation-finished(caseID,timestampNs)` events to a private regular progress file. The outer supervisor positively observes `generation-started`, starts its own monotonic per-case deadline at that observation, and enforces the 1,500 ms warm generation boundary without comparing helper timestamps or wall clocks. It sends TERM, waits a bounded grace period, then KILLs if needed; it waits for exit and publishes no evidence or summary. Forced termination is reported truthfully as non-cooperative in the error path. A separate monotonic whole-process timeout covers preflight/load/harness failure and is never used as the warm deadline.

Inputs are limited to 80 lexical tokens and maximum output tokens are input count plus 32. Generation is argmax/temperature 0 with thinking disabled. The Swift boundary uses fixed response limits of 65,536 bytes and 4,096 output characters; caller-supplied limits and replacement counts are not accepted.

Final publication uses private staging outside the repository and output tree. The canonical output directory is opened with `O_DIRECTORY|O_NOFOLLOW`, its device/inode is captured, and the identity is revalidated at publication. Evidence and summary are linked relative to the held directory descriptor; rollback unlinks relative to that descriptor. Existing destinations, output-directory replacement, and ancestor-symlink races fail closed without redirected writes.

## Contract tests

The fake suite never imports or loads the real model:

```sh
FLECK_QWEN_PYTHON_EXECUTABLE="/absolute/canonical/path/to/existing/python3.14" \
  sh Tools/QwenCleanupBenchmark/Tests/run-contract-tests.sh
```

Use the canonical regular-file path for the pinned executable under test, not a
symlink or path alias. The suite retains its existing interpreter, helper, and
validator digest checks.

It covers artifact mismatch before runtime/model load, full-inventory and tokenizer/chat-template tampering, denied network, poisoned ambient Python startup, duplicate/unknown/forged helper records, recursive nested duplicates in generation/offline/artifact/prompt, malformed and wrapper outputs, pinned runtime/provenance shape, exact envelope acceptance, protected-content rejection, one request/no retry, just-under and over-deadline termination from monotonic clocks, no late publication, symlink/path boundaries, and output-directory replacement races.

## Explicit real-model smoke

Run this only after the fake suite is green and only with the external paths present. The command writes evidence only under the explicit external output root:

```sh
export FLECK_QWEN_PYTHON_EXECUTABLE="/absolute/path/to/existing/python3.14"
export FLECK_QWEN_RUNTIME_SITE_PACKAGES="/absolute/path/to/existing/site-packages"
export FLECK_QWEN_MODEL_ROOT="/absolute/path/to/existing/qwen3.5-0.8b-model"
export FLECK_QWEN_OUTPUT_ROOT="/absolute/path/to/existing/output-root"

sh Tools/QwenCleanupBenchmark/run-qwen-cleanup-benchmark.sh \
  --smoke \
  --case-id en-filler-repetition-name
```

All four environment variables are required unless their corresponding CLI
options are supplied. They must identify existing canonical external paths;
the output root must be outside the repository and app bundles. The harness has
no private fallback and downloads nothing.

The smoke result is external benchmark evidence only. It does not change admission, integration, packaging, installer, release, or repository state.
