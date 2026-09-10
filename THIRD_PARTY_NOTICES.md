# Third-party notices

This file records the third-party boundaries for the source tree at the pinned
dependency revisions. It is an engineering inventory, not a substitute for
the exact license and NOTICE files required with a binary distribution.
Package lockfiles remain authoritative for resolved revisions.

Fleck's MPL-2.0 license applies only to covered Fleck-owned source and
documentation in the current tree. It does not relicense any dependency,
dataset, model, or other third-party material described here. Earlier revisions
remain subject to their accompanying license notices and terms.

## Documentation material

`CODE_OF_CONDUCT.md` is adapted from Contributor Covenant 3.0, stewarded by the
Organization for Ethical Source, and licensed under
[Creative Commons Attribution-ShareAlike 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
The file preserves the source link, adaptation statement, attribution, and
license link. It is not MPL-covered.

## Ordinary application and agent link graph

The ordinary `Fleck` application is first-party Swift/AppKit code. The bundled
`fleck-agent` links the Model Context Protocol Swift SDK's `MCP` library; that
library in turn uses Swift System, SwiftLog, and EventSource. SwiftNIO, Swift
Atomics, and Swift Collections are resolved in the root lockfile but are used
by a different SDK executable target and have not been shown to link into the
ordinary Fleck products. They must not be described as shipped without a final
link-graph check.

| Component | Pin | Terms and exact evidence |
| --- | --- | --- |
| Model Context Protocol Swift SDK | `a0ae212ebf6eab5f754c3129608bc5557637e605` | Mixed by file: Apache-2.0, unrelicensed MIT contributions, and CC BY 4.0 documentation. [Pinned LICENSE](https://github.com/modelcontextprotocol/swift-sdk/blob/a0ae212ebf6eab5f754c3129608bc5557637e605/LICENSE), SHA-256 `0382b0057770ca05e9c350a50aa3b1c1fea84da0bc81d723bf00b9aa841be58a`. Copyright 2024-2025 Model Context Protocol a Series of LF Projects, LLC. |
| EventSource | `a3a85a85214caf642abaa96ae664e4c772a59f6e` (`1.4.1`) | MIT. [Pinned LICENSE](https://github.com/mattt/EventSource/blob/a3a85a85214caf642abaa96ae664e4c772a59f6e/LICENSE.md), SHA-256 `2f9b695627d569a3ce452b2c03fdd34310df78c8ea94edfafd9ce38381e5b502`. Copyright 2025 Mattt. |
| SwiftLog | `a878e7f8f46cfc0e1125e565b5c08e7d5272dc9a` (`1.14.0`) | Apache-2.0. [Pinned LICENSE](https://github.com/apple/swift-log/blob/a878e7f8f46cfc0e1125e565b5c08e7d5272dc9a/LICENSE.txt), SHA-256 `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`; [pinned NOTICE](https://github.com/apple/swift-log/blob/a878e7f8f46cfc0e1125e565b5c08e7d5272dc9a/NOTICE.txt), SHA-256 `879b241d49b407215a0ad8e1c6a71c358d7b29591b090cf379d37a5f50cff918`. Copyright 2018, 2019 The SwiftLog Project. The NOTICE records derivation of a lock implementation and scripts from SwiftNIO. |
| Swift System | `50688cacbd41d547e9eb9f7a213542340b7c442b` (`1.7.5`) | Apache-2.0 with Runtime Library Exception. [Pinned LICENSE](https://github.com/apple/swift-system/blob/50688cacbd41d547e9eb9f7a213542340b7c442b/LICENSE.txt), SHA-256 `2245a990b635558be210fb3eb4f8a6f7a49aebc0fefbf5859146a65ddc7ddcf3`. |

The root lockfile also resolves the following packages. The selected `MCP`
library target does not use them, so they are recorded here without claiming
that their code ships in the ordinary app:

| Component | Pin | Terms and pinned evidence |
| --- | --- | --- |
| SwiftNIO | `0b18836bd8b0162e7e17a995a3fbee20ed8f3b2b` (`2.101.3`) | Apache-2.0. [LICENSE](https://github.com/apple/swift-nio/blob/0b18836bd8b0162e7e17a995a3fbee20ed8f3b2b/LICENSE.txt), SHA-256 `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`; [NOTICE](https://github.com/apple/swift-nio/blob/0b18836bd8b0162e7e17a995a3fbee20ed8f3b2b/NOTICE.txt), SHA-256 `d25ed2452b3476c342082d11e4e8bf5459174d2836124f842b499850bcebc50e`. |
| Swift Atomics | `0442cb5a3f98ab802acb777929fdb446bda11a34` (`1.3.1`) | Apache-2.0 with Runtime Library Exception. [LICENSE](https://github.com/apple/swift-atomics/blob/0442cb5a3f98ab802acb777929fdb446bda11a34/LICENSE.txt), SHA-256 `770af8291f708538d8ff885a0bbc4e045cd700531741c4f99528d435c14d7f55`. |
| Swift Collections | `a0cb0954ecb21e4e31b0070e6ed5674e8556685a` (`1.6.0`) | Apache-2.0 with Runtime Library Exception. [LICENSE](https://github.com/apple/swift-collections/blob/a0cb0954ecb21e4e31b0070e6ed5674e8556685a/LICENSE.txt), SHA-256 `770af8291f708538d8ff885a0bbc4e045cd700531741c4f99528d435c14d7f55`. |

The current ordinary app packaging script does not copy this repository's
license/notice set or the exact dependency licenses into the app bundle.
Binary distribution therefore remains blocked until packaging and link-graph
verification are completed.

## Enhanced candidate and Gemma helper graph

The enhanced route is compile-gated and is not an ordinary shipping feature.
It adds FluidAudio and, for the Gemma cleanup helper, the following exact
locked graph. These packages are permissively licensed, but any distributed
enhanced binary still needs the applicable verbatim license and NOTICE files.

| Component | Pin | License | License SHA-256 | Additional NOTICE SHA-256 |
| --- | --- | --- | --- | --- |
| [FluidAudio](https://github.com/FluidInference/FluidAudio/blob/19600a485baa4998812e4654b70d2bab8f2c9949/LICENSE) | `19600a485baa4998812e4654b70d2bab8f2c9949` | Apache-2.0 | `c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4` | — |
| [EventSource](https://github.com/mattt/EventSource/blob/86b5096ac59ab46e66bd1f6377c604bc1dab0bc2/LICENSE.md) | `86b5096ac59ab46e66bd1f6377c604bc1dab0bc2` | MIT | `2f9b695627d569a3ce452b2c03fdd34310df78c8ea94edfafd9ce38381e5b502` | — |
| [MLX Swift](https://github.com/ml-explore/mlx-swift/blob/0bb916c67f4b9e5c682cbe02a42c701c93ab5021/LICENSE) | `0bb916c67f4b9e5c682cbe02a42c701c93ab5021` | MIT | `44326a4ea062241ae6fc26ee2ec90bdc81af7eb7b9d3966181b733fa69d42057` | — |
| [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm/blob/bd4b7434e6bdb588c7ef55706ff8904cb7fd4c57/LICENSE) | `bd4b7434e6bdb588c7ef55706ff8904cb7fd4c57` | MIT | `7b1d86acac816ce8192209d7e01141c129b4d48d474c15cc5fb4af62f497c323` | — |
| [Swift Argument Parser](https://github.com/apple/swift-argument-parser/blob/6a52f3251125d74daf04fcbd5e6f08a75d074382/LICENSE.txt) | `6a52f3251125d74daf04fcbd5e6f08a75d074382` | Apache-2.0 with Runtime Library Exception | `770af8291f708538d8ff885a0bbc4e045cd700531741c4f99528d435c14d7f55` | — |
| [Swift ASN.1](https://github.com/apple/swift-asn1/blob/a9a5efd40eaf558a2bcd48d64b1d1646be686008/LICENSE.txt) | `a9a5efd40eaf558a2bcd48d64b1d1646be686008` | Apache-2.0 | `8c6db340475136df3c1201d458fa5755698eace76e510471ecc9d857d6083dac` | `11dd3b3b783e6ec26098dd38ebc962986ea109b85447e28e62867b83bd0f8c5b` |
| [Swift Collections](https://github.com/apple/swift-collections/blob/a0cb0954ecb21e4e31b0070e6ed5674e8556685a/LICENSE.txt) | `a0cb0954ecb21e4e31b0070e6ed5674e8556685a` | Apache-2.0 with Runtime Library Exception | `770af8291f708538d8ff885a0bbc4e045cd700531741c4f99528d435c14d7f55` | — |
| [Swift Crypto](https://github.com/apple/swift-crypto/blob/47d3869a7291f085c1fb9fb1e6d3b97a793f45c6/LICENSE.txt) | `47d3869a7291f085c1fb9fb1e6d3b97a793f45c6` | Apache-2.0 | `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` | `b3ddc2ae068e76b3beb71be03c0400f90090f9469aa491bf7b1ac42320af37b8` |
| [Swift Hugging Face](https://github.com/huggingface/swift-huggingface/blob/b721959445b617d0bf03910b2b4aced345fd93bf/LICENSE) | `b721959445b617d0bf03910b2b4aced345fd93bf` | Apache-2.0 | `4d6ad72952a8329063a71de28329b493de96cf57459e2ac217110d1a6a5f84ae` | — |
| [Swift Jinja](https://github.com/huggingface/swift-jinja/blob/7d0b8880ef8e567dd4e0089f8b99fb354129017c/LICENSE) | `7d0b8880ef8e567dd4e0089f8b99fb354129017c` | Apache-2.0 | `648b81e6c6f9975c3b6cf6d630229b6c8d6f1ddaef55f5770f576adda19f3495` | — |
| [Swift Numerics](https://github.com/apple/swift-numerics/blob/0c0290ff6b24942dadb83a929ffaaa1481df04a2/LICENSE.txt) | `0c0290ff6b24942dadb83a929ffaaa1481df04a2` | Apache-2.0 with Runtime Library Exception | `770af8291f708538d8ff885a0bbc4e045cd700531741c4f99528d435c14d7f55` | — |
| [Swift Syntax](https://github.com/swiftlang/swift-syntax/blob/79e4b74a295b6eb74a8b585e3a39d29e70c1dbd1/LICENSE.txt) | `79e4b74a295b6eb74a8b585e3a39d29e70c1dbd1` | Apache-2.0 with Runtime Library Exception | `770af8291f708538d8ff885a0bbc4e045cd700531741c4f99528d435c14d7f55` | — |
| [Swift Transformers](https://github.com/huggingface/swift-transformers/blob/b38443e44d93eca770f2eb68e2a4d0fa100f9aa2/LICENSE) | `b38443e44d93eca770f2eb68e2a4d0fa100f9aa2` | Apache-2.0 | `648b81e6c6f9975c3b6cf6d630229b6c8d6f1ddaef55f5770f576adda19f3495` | — |
| [yyjson](https://github.com/ibireme/yyjson/blob/8b4a38dc994a110abaec8a400615567bd996105f/LICENSE) | `8b4a38dc994a110abaec8a400615567bd996105f` | MIT | `45e384d3d52c73cba3a64d6e6c25d47cd738cd8a55c30629e3201046eda62947` | — |

Swift ASN.1's NOTICE identifies derivations of scripts from SwiftNIO and Swift
OpenAPI Generator. Swift Crypto's NOTICE identifies Google Wycheproof test
vectors and derivations from SwiftNIO. Those notices must accompany a
distribution when they pertain to the shipped payload.

## Website runtime

The current plain-Vite website runtime graph is separate from its build
toolchain:

| Component | Version | Terms |
| --- | --- | --- |
| GSAP | `3.15.0` | Copyright 2026, GreenSock. [GSAP Standard License](https://gsap.com/standard-license/), custom and not OSI-approved. The official terms permit ordinary commercial websites at no charge but prohibit competing no-code visual animation builders and removing or altering proprietary notices or branding. Preserve GSAP's complete distributed `@license` banner. GSAP is not MPL-covered. |
| React | `19.2.8` | MIT; exact npm license SHA-256 `da6d3703ed11cbe42bd212c725957c98da23cbff1998c05fa4b3d976d1a58e93`. |
| React DOM | `19.2.8` | MIT; exact npm license SHA-256 `da6d3703ed11cbe42bd212c725957c98da23cbff1998c05fa4b3d976d1a58e93`. |
| Scheduler | `0.27.0` | MIT; exact npm license SHA-256 `da6d3703ed11cbe42bd212c725957c98da23cbff1998c05fa4b3d976d1a58e93`. |

The exact React, React DOM, and Scheduler license files state: “Copyright (c)
Meta Platforms, Inc. and affiliates.” Their complete MIT text must accompany a
distribution that includes copies or substantial portions of those packages.

The build tool is Vite 8.2.2. The Cloudflare Vite plugin, Wrangler
configuration, and worker used by earlier revisions are not part of the current
graph; those revisions remain subject to their accompanying terms. The current
source tree includes the complete npm license compilation at
`website/public/THIRD_PARTY_LICENSES.txt`. Do not distribute `node_modules`, a
build image, or tool binaries as though the four-row runtime inventory covers
them. A future deployment must verify that GSAP's proprietary banner and the
complete notice artifact survive the deployed output.

## FLEURS-derived data

Tracked benchmark metadata, reference text, and derived evaluation material
use parts of **FLEURS: Few-shot Learning Evaluation of Universal
Representations of Speech**, from `google/fleurs` at immutable revision
[`a3c817cbf7c08863e0c472861c7c39e27ce7f38e`](https://huggingface.co/datasets/google/fleurs/tree/a3c817cbf7c08863e0c472861c7c39e27ce7f38e).
The dataset card declares [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
The FLEURS-derived portions are not MPL-covered. Fleck-authored schemas,
metadata fields, synthetic cases, and tooling that share a file with those
portions remain under the repository's MPL terms; the mixed file does not
erase either license boundary.

Fleck selected 12 English and 12 Mandarin validation records; retained
reference text and metadata; produced ASR and cleanup outputs for evaluation;
and created 12 artificial bilingual composites by concatenating selected
recordings with fixed silence gaps. Those composites are explicitly not
natural code-switch evidence. FLEURS audio is downloaded separately and is not
tracked in this repository.

The affected tracked mixed-data files include:

- `Tools/LocalDictationCandidateAdapters/Benchmarks/Corpus/manifest-v1.json`
- `Tools/LocalDictationCandidateAdapters/Benchmarks/Candidates/whisper-small-control.json`
- `Tools/QwenCleanupBenchmark/Qualification/corpus-v1.json`
- `Tests/Fixtures/local-dictation-candidate-benchmark-v2.json`

Please cite the source dataset as supplied by its pinned dataset card:

> Alexis Conneau, Min Ma, Simran Khanuja, Yu Zhang, Vera Axelrod, Siddharth
> Dalmia, Jason Riesa, Clara Rivera, and Ankur Bapna. “FLEURS: Few-shot
> Learning Evaluation of Universal Representations of Speech.” arXiv preprint
> arXiv:2205.12446 (2022). <https://arxiv.org/abs/2205.12446>

## Models and research-only candidates

No model weights are tracked in this repository. Model metadata and source
links do not place a model under Fleck's MPL.

- Parakeet TDT 0.6B V2 Core ML is an external CC-BY-4.0 model candidate. Its
  base-model terms, attribution placement, modification statement, and release
  approval remain separate gates.
- Gemma 3 1B is external and subject to the custom Gemma Terms of Use. See
  `Sources/FleckApp/Resources/GemmaCleanupNotice.md`.
- Qwen, Whisper, and Nemotron entries under `Tools/` are developer research or
  benchmark candidates. Their metadata does not authorize redistributing
  weights, converted archives, runtimes, or transitive native components.

Do not distribute or enable a model route until its exact payload, complete
terms and attribution, required modification notices, and product release gate
have been reviewed.
