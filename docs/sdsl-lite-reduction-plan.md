# sdsl-lite dependency audit and reduction plan

## Current integration points in this repository

- Build integration currently clones the full `sdsl-lite` repository and runs `install.sh` into `src/thirdparty/{include,lib}`.
- All four binaries (`TeraMS`, `TeraLCP`, `TeraIndex`, `TeraMEM`) link against `-lsdsl`.
- Project source code includes only one sdsl header directly: `sdsl/int_vector.hpp`.

## Functionality actually used from sdsl

From project source under `src/include` and `src/*/*.cpp`, usage appears limited to:

1. **Bit-packed vectors and integer vectors**
   - `sdsl::int_vector<>`
   - `sdsl::bit_vector`
   - `get_int` / `set_int` on `bit_vector` storage (via `packedTripleVector`)
   - width-aware construction and resize/clear-by-assignment idioms

2. **Bit utilities**
   - `sdsl::bits::hi` (for width computation)

3. **Vector utility helpers**
   - `sdsl::util::expand_width`
   - `sdsl::util::bit_compress`

4. **Serialization framework**
   - `sdsl::serialize(...)`
   - `sdsl::load(...)`
   - `sdsl::structure_tree_node`
   - `sdsl::structure_tree::{add_child,add_size}`
   - `sdsl::util::class_name(...)`

5. **Diagnostics / reporting only**
   - `sdsl::size_in_bytes(...)`
   - `sdsl::write_structure<sdsl::HTML_FORMAT>(...)`
   - `sdsl::memory_monitor` references (mostly optional/commented)

No wavelet trees, compressed suffix arrays, rmq/cst structures, rank/select support types, or coders are used by project code.

## Practical interpretation

The project currently depends on a broad sdsl installation mechanism, but the **runtime data-structure requirements are narrow**:

- packed integer vector storage
- a small part of generic serialization
- minimal bit utility helpers

This suggests two viable reduction tracks:

## Track A (fastest): keep sdsl-lite, prune to a vendored subset

### Goal
Replace full `git clone + install.sh` with a fixed local subset under `src/thirdparty/sdsl_subset` and build only what is required.

### Steps
1. **Pin and inventory**
   - Record current sdsl-lite commit hash used in builds.
   - Record exported symbols actually pulled by each binary.
2. **Header minimization pass**
   - Start from `int_vector.hpp` and follow only transitive includes needed to compile current project.
   - Copy required headers into `src/thirdparty/sdsl_subset/include/sdsl`.
3. **Source/object minimization pass**
   - Build once with `-Wl,--trace-symbol`/`nm` assisted analysis to identify required non-header symbols.
   - Keep only required `.cpp` compilation units in a tiny `libsdsl_subset.a`.
4. **Build-system switch**
   - Replace `src/thirdparty/Makefile` cloning/install step with local subset build.
   - Keep include/lib interface stable for upstream code.
5. **Compliance artifact**
   - Add a generated `THIRD_PARTY_NOTICES.md` section describing source commit + retained files list + licenses.

### Exit criteria
- Clean build of all binaries using only `sdsl_subset`.
- Binary/test parity against baseline.
- Reproducible script that re-derives subset from pinned upstream commit.

## Track B (strategic): remove sdsl dependency progressively

### Goal
Introduce a project-owned compatibility layer and replace sdsl APIs incrementally.

### Steps
1. **Introduce abstraction layer**
   - Add `src/include/util/compact_int_vector.h` and serialization wrappers.
   - Refactor project code to call wrappers (no direct `sdsl::...` in algorithmic code).
2. **Implement equivalent primitives**
   - Implement packed bit storage (`get_int`/`set_int`) and width-managed vectors.
   - Implement project-local serialization format compatibility adapters.
3. **Feature-flag backend**
   - `TERATOOLS_USE_SDSL=ON/OFF` build option.
   - Validate both backends in CI.
4. **Cutover**
   - Make non-sdsl backend default.
   - Remove sdsl from mandatory build path.

### Exit criteria
- All targets build and run with `TERATOOLS_USE_SDSL=OFF`.
- Index read/write compatibility expectations explicitly documented and tested.

## Recommended sequence

1. Execute **Track A first** to quickly reduce supply-chain/build surface area.
2. While doing that, add wrapper interfaces required by **Track B** so future migration is low risk.
3. Defer serialization format changes until wrappers are in place and compatibility tests exist.

## Immediate next actions (concrete)

1. Add `tools/audit_sdsl_usage.sh` to automatically:
   - list direct `sdsl::` API uses in non-thirdparty source
   - list linked sdsl symbols per binary
2. Add a `docs/sdsl-subset-filelist.txt` generated from a first minimization attempt.
3. Update `src/thirdparty/Makefile` to optionally build from local subset when present.
4. Add CI job matrix entry validating baseline/full sdsl and subset sdsl builds.

