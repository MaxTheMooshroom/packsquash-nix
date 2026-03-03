(final: prev: {
  cargo-nightly = prev.rust-bin.selectLatestNightlyWith (
    toolchain: toolchain.default
  );

  rustc-nightly = prev.rust-bin.selectLatestNightlyWith (
    toolchain: toolchain.default
  );
})
