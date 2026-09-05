# bpftop

Dynamic real-time view of running eBPF programs
([Netflix/bpftop](https://github.com/Netflix/bpftop)).

## Install / build

The package uses the Rust toolchain from the `packages` feed
(`feeds/packages/lang/rust`), so first make sure it is installed in the build:

```
./scripts/feeds update -a
./scripts/feeds install -a
```

then enable `CONFIG_PACKAGE_bpftop`. Building requires:

- the OpenWrt Rust host toolchain (built automatically via `rust/host`),
  i.e. network access to crates.io,
- **clang with the `bpf` target on the build host** — `bpftop`'s `build.rs`
  compiles its embedded `pid_iter.bpf.c` skeleton at build time using
  `libbpf-cargo`, which shells out to `clang` (system/Linux-distribution
  clang is fine),
- `libelf` (headers + runtime), pulled in automatically via `DEPENDS`.

Only architectures supported by the Rust toolchain build
(`RUST_ARCH_DEPENDS`) are selectable.

## Usage

Run as root on a kernel with BTF enabled (`CONFIG_DEBUG_INFO_BPF`,
`CONFIG_DEBUG_INFO_BTF=y`):

```
bpftop [OPTIONS]
```

Interactively shows, for each running BPF program: average runtime, events
per second, and an estimated CPU %. Keys: `s`/`b`/`m` change the sort/sum
order, `/` filters, `q` or Ctrl-C quits. See `bpftop --help` for the full
list (e.g. `--cpu`, `--sort`, `--elapsed`).