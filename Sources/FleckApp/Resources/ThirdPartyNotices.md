# Third-party notices for Fleck app candidates

This bundled summary separates the ordinary application graph from optional
enhanced-model components. It does not relicense third-party material under
Fleck's MPL-2.0 license and does not replace verbatim license or NOTICE files
required for binary distribution. The repository-level inventory is
`THIRD_PARTY_NOTICES.md`.

## Ordinary application and `fleck-agent`

`fleck-agent` links the Model Context Protocol Swift SDK's `MCP` library,
which uses Swift System, SwiftLog, and EventSource. SwiftNIO, Swift Atomics,
and Swift Collections are resolved in the root lockfile but have not been
shown to link into the ordinary products.

| Component | Pin | Terms and pinned evidence |
| --- | --- | --- |
| Model Context Protocol Swift SDK | `a0ae212ebf6eab5f754c3129608bc5557637e605` | Apache-2.0, unrelicensed MIT contributions, and CC BY 4.0 documentation, by file. [LICENSE](https://github.com/modelcontextprotocol/swift-sdk/blob/a0ae212ebf6eab5f754c3129608bc5557637e605/LICENSE), SHA-256 `0382b0057770ca05e9c350a50aa3b1c1fea84da0bc81d723bf00b9aa841be58a`. Copyright 2024-2025 Model Context Protocol a Series of LF Projects, LLC. |
| EventSource | `a3a85a85214caf642abaa96ae664e4c772a59f6e` (`1.4.1`) | MIT. [LICENSE](https://github.com/mattt/EventSource/blob/a3a85a85214caf642abaa96ae664e4c772a59f6e/LICENSE.md), SHA-256 `2f9b695627d569a3ce452b2c03fdd34310df78c8ea94edfafd9ce38381e5b502`. Copyright 2025 Mattt. |
| SwiftLog | `a878e7f8f46cfc0e1125e565b5c08e7d5272dc9a` (`1.14.0`) | Apache-2.0. [LICENSE](https://github.com/apple/swift-log/blob/a878e7f8f46cfc0e1125e565b5c08e7d5272dc9a/LICENSE.txt), SHA-256 `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`; [NOTICE](https://github.com/apple/swift-log/blob/a878e7f8f46cfc0e1125e565b5c08e7d5272dc9a/NOTICE.txt), SHA-256 `879b241d49b407215a0ad8e1c6a71c358d7b29591b090cf379d37a5f50cff918`. Copyright 2018, 2019 The SwiftLog Project. |
| Swift System | `50688cacbd41d547e9eb9f7a213542340b7c442b` (`1.7.5`) | Apache-2.0 with Runtime Library Exception. [LICENSE](https://github.com/apple/swift-system/blob/50688cacbd41d547e9eb9f7a213542340b7c442b/LICENSE.txt), SHA-256 `2245a990b635558be210fb3eb4f8a6f7a49aebc0fefbf5859146a65ddc7ddcf3`. |

## Enhanced local candidate

The enhanced route is compile-gated. FluidAudio is pinned at
[`19600a485baa4998812e4654b70d2bab8f2c9949`](https://github.com/FluidInference/FluidAudio/commit/19600a485baa4998812e4654b70d2bab8f2c9949)
and is Apache-2.0. Its pinned [LICENSE](https://github.com/FluidInference/FluidAudio/blob/19600a485baa4998812e4654b70d2bab8f2c9949/LICENSE)
has SHA-256
`c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4`.

The Gemma cleanup helper additionally resolves EventSource, MLX Swift, MLX
Swift LM, Swift Argument Parser, Swift ASN.1, Swift Collections, Swift Crypto,
Swift Hugging Face, Swift Jinja, Swift Numerics, Swift Syntax, Swift
Transformers, and yyjson. Exact pins, license identities, digests, and
pertinent Swift ASN.1/Swift Crypto NOTICE entries are recorded in
`THIRD_PARTY_NOTICES.md`. They are MIT or Apache-2.0, with the Swift runtime
library exception where identified; model terms remain separate.

## Parakeet TDT 0.6B V2 Core ML model

The Enhanced Local model is
[`FluidInference/parakeet-tdt-0.6b-v2-coreml`](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/tree/ee09c569f73759e6d44c9bd16766f477b2b36d39)
at immutable revision
`ee09c569f73759e6d44c9bd16766f477b2b36d39`. Its pinned
[model card](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/blob/ee09c569f73759e6d44c9bd16766f477b2b36d39/README.md)
declares [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) and
identifies
[`nvidia/parakeet-tdt-0.6b-v2`](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)
as its base model.

The model is external, is not MPL-covered, and is not tracked in this
repository. Distribution and release remain blocked pending exact creator and
base-model attribution, a modification statement where applicable,
attribution placement, payload verification, and product approval.

## Distribution status

The current packaging paths do not yet include the complete verbatim
license/NOTICE corpus for the ordinary or enhanced link graphs. Do not treat
this summary alone as binary-distribution clearance.
