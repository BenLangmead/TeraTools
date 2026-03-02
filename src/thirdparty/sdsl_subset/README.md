# Vendored sdsl subset

This directory contains a curated subset of `sdsl-lite` files required by TeraTools.

## Build

```bash
make -C src/thirdparty/sdsl_subset install PREFIX=..
```

This installs:
- headers into `src/thirdparty/include/sdsl`
- `libsdsl.a` into `src/thirdparty/lib`

## Regeneration

When `src/thirdparty/sdsl-lite` is available locally, regenerate the subset with:

```bash
tools/vendor_sdsl_subset.sh
```

The pinned upstream commit and copied file inventory are tracked in `MANIFEST.md`.

## Local adaptation

`ram_filebuf.hpp` and `ram_filebuf.cpp` are included to satisfy `sfstream` dependencies in
this reduced build configuration.
