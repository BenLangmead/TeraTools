# Vendored sdsl subset

This directory contains a curated subset of `sdsl-lite` files required by TeraTools.

## Upstream credit and provenance

This subset is derived from **sdsl-lite** by **Simon Gog** and contributors.
Many files in this directory are copied from upstream sdsl-lite and remain under
sdsl-lite's licensing terms (see `COPYING`).

The exact upstream source used for this subset is:
- Repository: `https://github.com/simongog/sdsl-lite`
- Commit: `c32874cb2d8524119f25f3b501526fe692df29f4`

## Included headers
- `include/sdsl/bits.hpp`
- `include/sdsl/config.hpp`
- `include/sdsl/int_vector.hpp`
- `include/sdsl/int_vector_buffer.hpp`
- `include/sdsl/io.hpp`
- `include/sdsl/iterators.hpp`
- `include/sdsl/memory_management.hpp`
- `include/sdsl/ram_filebuf.hpp`
- `include/sdsl/ram_fs.hpp`
- `include/sdsl/sdsl_concepts.hpp`
- `include/sdsl/sfstream.hpp`
- `include/sdsl/structure_tree.hpp`
- `include/sdsl/uintx_t.hpp`
- `include/sdsl/util.hpp`

## Included source files
- `src/bits.cpp`
- `src/io.cpp`
- `src/memory_management.cpp`
- `src/ram_filebuf.cpp`
- `src/ram_fs.cpp`
- `src/sfstream.cpp`
- `src/structure_tree.cpp`
- `src/util.cpp`

## Build

```bash
make -C src/thirdparty/sdsl_subset install PREFIX=..
```

This installs:
- headers into `src/thirdparty/include/sdsl`
- `libsdsl.a` into `src/thirdparty/lib`

## Local adaptation

`ram_filebuf.hpp` and `ram_filebuf.cpp` are included to satisfy `sfstream` dependencies in
this reduced build configuration.
