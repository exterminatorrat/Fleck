# Local writing evaluation archive

This evaluator-only index preserves content-free historical identities. It is not a model catalog, runtime configuration, installation manifest, recommendation source, package receipt, or admission record. All four rows remain `documentedOnly`; missing proof is never inferred from nearby commits or equivalent patches.

The Swift index is authoritative for ordering and exact-ID lookup. This page is a reviewed status view of the same immutable commits, SHA-256 identities, dispositions, and missing-binding reasons. Documentary labels are not authority.

## Status index

| Stable ID | Family | Record | Corpus class | Evidence tier | Disposition | Missing bindings |
| --- | --- | --- | --- | --- | --- | --- |
| `nemotron-asr-final-benchmark` | Nemotron | ASR benchmark | historical ASR benchmark | historical benchmark | benchmark only | `sourceHarnessBinding` |
| `qwen-asr-final-benchmark` | Qwen ASR | ASR benchmark | historical ASR benchmark | historical benchmark | historical | `exactFleckSource`, `sourceHarnessBinding` |
| `qwen-cleanup-rejected-qualification` | Qwen cleanup | cleanup qualification | historical cleanup qualification | historical qualification | rejected: `unexpectedLexicalChange` | `hardwareIdentity` |
| `whisper-asr-final-benchmark` | Whisper | ASR benchmark | historical ASR benchmark | historical benchmark | historical | `exactOSBuild`, `sourceHarnessBinary` |

Nemotron's recorded `automatedCandidatePass=false` remains a benchmark-only observation. It is not converted into an accuracy rejection. The Qwen cleanup row retains the stated rejection because its qualification outcome records an unexpected lexical change.

## Immutable source history

### Whisper

- Adapter: `3c51adf30f737f4f18243af3efb83202939be5e0`
- Hardening: `85381a88b619121fcb46a5d576b44e59816b1109`
- Divergent correction: `a41aef534b626860c9f1e93d3067bc8958674341`; reason `notSuccessor` from the hardening commit
- Final benchmark: `ecd69f9d8947b74074de30b11864db5f72267b27`
- Identical-patch benchmark alias: `af49c07aa1276d54b3d6e7a934e7fbdebc98a7fa`, canonicalized to the final benchmark above

Available SHA-256 bindings:

- Corpus: `d3890ec3577d72334157c4fccc27d6dc69a9e3610e8185d7a6bac6cba86893d0`
- Hardware: `d0e9e907d90f84ed7c6c3198b948ed5ddac200d0d0b4c9ad58ab6044e6cc1464`
- Profile: `1644116843e508b30587968a9e05823c06e134922c0194950d0b2954b0984bbc`
- Result: `d88baeb70ffff523b34b58411e309ead2d9fe4803dc813bc96ce1ac436c6c040`

### Nemotron

- Helper: `44a9942c96a25c7b117dae4fd49eb3b3dcba64fc`
- Hardening: `84bc6bffbd6c75469764112148a3882a685c31d5`
- Adapter: `beaef43acec13c3f80ee2fce8fe4a978e0068c56`

Available SHA-256 bindings:

- Corpus: `d3890ec3577d72334157c4fccc27d6dc69a9e3610e8185d7a6bac6cba86893d0`
- Hardware: `f98aff6b2c7995a39f6f22293a55d862c9da02f0172e591b442b50a1544678e1`
- Profile: `89e49a4a67156595bd352326c42e93c41a997be369e4001dbbb66cf327cf8acd`
- Result: `ce3d99da373ccee73eb53e29bc5eddd4f85e2e60d736aabfb895bf3792f9a6f3`

### Qwen ASR

- Final benchmark: `01904f8b23bc1376c4aad886126472379704241c`
- Helper: `2ca49f3e0f61d79b0fda1d236991db651a78de30`
- Hardening redo: `4dfeb922004c8ef099811e3e6fdf2b931e554efe`
- Adapter experiment and historical hardening alias: `71739d6a24fc46327950a35370e616b25cb47652`

Available SHA-256 bindings:

- Corpus: `afa77705f55efe8afced980a4f01a886dbbccc839e4806c69f6a18c452ec32cd`
- Hardware: `f98aff6b2c7995a39f6f22293a55d862c9da02f0172e591b442b50a1544678e1`
- Profile: `2e73a9b05dd315aa0902360746b4a699abea69b82cd17b8ddfa80c899fe12b42`
- Result: `4ca3aba3ed9122ce9cafe16171970c2f45810524dbf6dbbc6095db81c1725f9b`

### Qwen cleanup

- Qualification harness: `e662b1fad117ef2eab32c578db2edf9743bba81b`

Available SHA-256 bindings:

- Corpus: `08acf8d411d1aa3b2880124cfbb711085bd6b94a2352bfbcc644c0edf8071fd8`
- Outcome: `3d18bfb90bd08bd423977456967872f7ec6569ccf13bfbb1073638dff7b2452c`
- Profile: `95daece6fb1e3a1e8f23cfcbe2f74494f315d307b641033685b50106f7647783`
- Provenance: `6b94c79eb8e071d2f085c4955ddd600b49da7c818d8422b53e5147a9296d9cbf`
- Qualification report: `9604fe5bc5ce29b04e49eccc7f681c8856591b577cf97e514ba034d988901bdd`

## Proof boundary

The archive records historical benchmark or qualification identity only. It contains no evaluation cases, audio, transcripts, private locations, model artifacts, retrieval metadata, mutable download reference, resource sizing, license/install state, selectable configuration, recommendation state, or release claim. Reopening any row requires a new evidence packet with every source, profile, corpus, hardware, and result binding; this archive alone cannot admit or reject a future candidate.
