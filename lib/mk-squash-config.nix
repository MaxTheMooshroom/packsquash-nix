{ lib, writeText, ... }@pkgs:
{
  /**
    The absolute or relative path to the directory where the pack
    that will be optimized resides.
  */
  pack_directory ? ./.,

  /**
    If true, this option makes PackSquash try to compress files
    whose contents are already compressed before adding them to
    the generated ZIP file, after all the file type-specific
    optimizations have been applied.

    This can squeeze in some extra savings at the cost of noticeably
    increased pack processing times. Currently, Ogg and PNG assets
    are the only already compressed files affected by this option,
    but this may change in the future.
  */
  recompress_compressed_files ? false,

  /**
    
  */
  perFileConfigs ? {},

  ...
}:
  writeText ''
    pack_directory=${pack_directory}

  ''
