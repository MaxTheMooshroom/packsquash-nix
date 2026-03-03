{ lib, writeText, ... }@pkgs:
let
  inherit (lib) types;

  mkOption = type: default: description:
    lib.mkOption { inherit default description; type = types.uniq type; };

  mkOptionNull = type: description:
    lib.mkOption {
      inherit description;
      type = types.uniq (types.nullOr type);
      default = null;
    };

  mkOptionNoDefault = type: description:
    lib.mkOption { inherit description; type = types.uniq type; };

  enumStr = enum:
    types.addCheck
      (types.enum enum)
      (builtins.all builtins.isString);

  separatedEnum = sep: enum:
    types.coercedTo
      (types.listOf (enumStr enum))
      (builtins.concatStringsSep sep)
      types.str;

  module = {
    options = {
      pack_directory = mkOptionNoDefault
        (types.addCheck types.path lib.pathIsDirectory)
        ''
        The absolute or relative path to the directory where the pack
        that will be optimized resides.

        If you use a literal string (i.e., surround the path with single
        quotes, `'like this'`) you won't need to escape any characters,
        but you won't be able to write paths that contain a single quote.
        On the other hand, if you use basic strings (i.e., surround the
        path by double quotes, `"like this"`), you will need to escape
        double quotes, backslashes, and other special characters defined by
        the TOML specification, but you will be able to write paths that
        contain a single quote. For more details about how strings are
        parsed, please read the TOML specification.
      '';

      recompress_compressed_files = mkOption types.bool false ''
        If `true`, this option makes PackSquash try to compress files
        whose contents are already compressed before adding them to the
        generated ZIP file, after all the file type-specific optimizations
        have been applied. This can squeeze in some extra savings at the
        cost of noticeably increased pack processing times. Currently,
        Ogg and PNG assets are the only already compressed files affected
        by this option, but this may change in the future.
      '';

      zip_compression_iterations = mkOption types.ints.u8 20 ''
        The number of Zopfli compression iterations that PackSquash will
        do when compressing a file of 1 MiB magnitude just before it is
        added to the generated ZIP file. This affects files whose contents
        are not already compressed or all files if
        [`recompress_compressed_files`](#recompress_compressed_files)
        is enabled.

        A higher number of iterations means that bigger files will be
        subject to more compression iterations, which may lead to higher
        space savings but is slower. Lower numbers imply that, in general,
        fewer compression iterations will be done, which is quicker but
        reduces space savings.

        Note that PackSquash calculates the exact number of iterations for
        a file depending on its size, so this number of iterations only
        guides that computation. More precisely, PackSquash targets a
        reference compression time, so smaller files will be compressed
        more, and larger files will be compressed less. Also, the file size
        is converted into a non-linear magnitude that grows slower than
        the file size itself (in mathematical terms, the order of the
        function is that of a fractional power, which is less than linear),
        and this magnitude is what is really used to compute the number of
        iterations. A consequence of this design is that PackSquash will
        be "hesitant" to reduce the number of iterations for bigger files
        to meet the target time, exceeding it, but not by too much.

        Unless set to zero, the number of iterations is clamped to the
        [1, 20] interval, so using values outside that interval for this
        option will only change the magnitude threshold where iterations
        start being reduced to meet a target time.

        Zero is a special case: no file will be compressed, no matter
        its size. This is useful to speed up the process without sacrificing
        file-specific optimization techniques. It might also speed up the
        loading of your pack by Minecraft clients because they won't have
        to decompress any file, which is a bottleneck, especially with the
        advent of fast storage devices. The obvious downside is that the
        generated ZIP files will likely be larger, which increases bandwidth
        requirements. However, if the decompression speed is much greater
        than the storage device speed (i.e., a beefy CPU is paired with a
        slow HDD, for example), Minecraft clients may take longer to load
        the pack.
      '';

      automatic_minecraft_quirks_detection = mkOption types.bool true ''
        When this option is set to `true`, PackSquash will try to
        automatically deduce an appropriate set of Minecraft quirks that
        affect how pack files can be optimized by looking at the pack files.
        This automatic detection works fine in most circumstances, but
        because quirks affect specific Minecraft versions, and maybe only
        under some conditions, it might be inexact.

        If you exactly know what quirks affect your pack and do not want
        PackSquash to come up with its own set of quirks to work around,
        set this option to `false`, and configure
        [`work_around_minecraft_quirks`](#work_around_minecraft_quirks)
        accordingly. Otherwise, you can leave it set to `true`.

        Please note that the automatic Minecraft quirks detection may
        validate and process the contents of the `pack.mcmeta` file, even
        if [`validate_pack_metadata_file`](#validate_pack_metadata_file) and
        [`automatic_asset_types_mask_detection`](#automatic_asset_types_mask_detection)
        are set to `false`. To prevent PackSquash from validating that
        file, these options should be all set to `false`.
      '';

      work_around_minecraft_quirks = mkOption
        (separatedEnum "," [
          "grayscale_images_gamma_miscorrection"
          "restrictive_banner_layer_texture_format_check"
          "bad_entity_eye_layer_texture_transparency_blending"
          "java8_zip_parsing"
          "ogg_obfuscation_incompatibility"
          "png_obfuscation_incompatibility"
        ]) [] ''
          Some Minecraft versions have some quirks that limit how some
          files can be compressed before they stop being interpreted
          correctly by the game. PackSquash can work around these quirks,
          but doing so may come at the cost of reduced space savings,
          increased processing times, or other undesirable consequences,
          so such workarounds should only be done if a pack is affected
          by them. This option allows to manually specify a comma-separated
          list of quirks that will be worked around if
          [`automatic_minecraft_quirks_detection`](#automatic_minecraft_quirks_detection)
          is set to `false`. The following quirks are supported:

          - `grayscale_images_gamma_miscorrection`: older versions of
            Minecraft (probably all versions since 1.6 until 1.13 are affected)
            assume that grayscale images are in a fairly uncommon color space
            instead of the more common sRGB space presumed for the rest of
            color types. Because PackSquash can compress full-color images that
            only have gray pixels to actual grayscale format to save space,
            affected Minecraft versions display those images with colors that
            look "washed out". The workaround implemented for this quirk stops
            PackSquash from trying to reduce color images to grayscale format
            under any circumstances, which may hurt compression.

          - `restrictive_banner_layer_texture_format_check`: older versions
            of Minecraft (probably all versions from 1.6 until 1.13 are
            affected) require banner and shield layer textures to be stored
            in RGBA format, or else the layers they represent won't be applied
            at all, even if the palette contains transparency data. PackSquash
            can convert images encoded in RGBA format to palette format to save
            space, triggering this quirky behavior in affected versions. This
            workaround stops PackSquash from changing the color format of the
            affected textures to a palette, which includes color quantization,
            as it is used to generate a palette. This incurs some space costs.

          - `bad_entity_eye_layer_texture_transparency_blending`: Minecraft
            versions older than 24w40a (1.21.2) overlay entity layer textures
            in a way that does not rightly account for transparency, taking
            into account their color and not only their transparency values
            as blending coefficients to use for overlying that texture
            (see [MC-235953](https://bugs.mojang.com/browse/MC-235953)).
            PackSquash can change the color of transparent pixels, triggering
            this behavior. This workaround stops PackSquash from changing the
            color of transparent pixels and quantizing the pixels to a palette
            to reduce texture file size, as both optimizations do not guarantee
            that the color of transparent pixels will stay the same.

          - `java8_zip_parsing`: the latest Minecraft versions, from 1.17
            onwards, are compiled for Java 16+, which means that they do not
            support older Java versions. On the other hand, Java 8 was used
            almost ubiquitously with older Minecraft clients, especially in
            modded environments. However, a lot of things have changed in newer
            Java versions, including low-level details of how ZIP files are
            parsed. When a ZIP specification conformance level that adds
            extraction protection is used, this workaround tells PackSquash to
            use obfuscation techniques that work fine with Java 8. This comes
            at the cost of protection that is a bit different, but the small
            differences will extremely likely not matter in protection strength.
            Compressibility can be impacted negatively, though. This quirk
            does not have any effect if an affected ZIP specification
            conformance level is not chosen or if the Minecraft client is
            run using newer Java versions.

          - `ogg_obfuscation_incompatibility`: not all Minecraft versions
            are compatible with the techniques PackSquash uses to obfuscate
            Ogg Vorbis files. Currently, only versions from 1.14 to 24w14a
            (1.20.5) reliably support obfuscated files; other versions may
            display console errors or even freeze when attempting to play
            obfuscated sounds. This workaround disables obfuscation for any
            Ogg Vorbis files generated by PackSquash, allowing the pack to
            work across all Minecraft versions, at the cost of no obfuscation.
            Note that, since multiple Minecraft versions share the same pack
            format, the autodetection code for this quirk will err on the
            safe side and consider slightly more Minecraft versions to be
            affected than necessary.

          - `png_obfuscation_incompatibility`: not all Minecraft versions
            are compatible with the techniques PackSquash uses to obfuscate
            PNG files. Currently, only versions from 1.14 onwards support
            obfuscated textures; other versions may display errors when the
            affected textures are loaded. This workaround disables obfuscation
            for any PNG files generated by PackSquash, allowing the pack to
            work across all Minecraft versions, at the cost of no obfuscation.

          When
          [`automatic_minecraft_quirks_detection`](#automatic_minecraft_quirks_detection)
          is set to `true`, PackSquash will use an automatically detected
          set of quirks no matter what, ignoring the value of this option.
        '';

      automatic_asset_types_mask_detection = mkOption types.bool true ''
        By default, PackSquash will attempt to automatically deduce the
        appropriate setf pack files to include in the generated ZIP by
        checking what Minecraft versions it targets, according to the pack
        format version. This works fine in most circumstances and saves space
        if the pack contains legacy or too new files for the targeted
        Minecraft version, but it might be undesirable sometimes.

        If you want PackSquash to include every pack file it recognizes and
        is enabled in [`allow_mods`](#allow_mods) no matter what, set this
        option to `false`. Otherwise, leave it set to `true` to let it
        exclude files that are known to be not relevant.

        When this option is set to `true`, the `pack.mcmeta` file may be
        read and validated, even if
        [`validate_pack_metadata_file`](#validate_pack_metadata_file) and
        [`automatic_minecraft_quirks_detection`](#automatic_minecraft_quirks_detection)
        are set to `false`. To guarantee that file is not read no matter
        what, these options should be all set to `false`.
      '';

      allow_mods = mkOption (separatedEnum "," [
          "OptiFine"
          "Minecraft Transit Railway 3"
        ]) [] ''
          PackSquash supports pack files that are only consumed by certain
          Minecraft mods, but, in the interest of optimizing packs as much
          as possible, it assumes that mod-specific files will not be used
          by the game by default and discards (skips) them from the generated
          ZIP file. This will break your pack unless you tell PackSquash
          about the involved mods via this option, whose value is a
          comma-separated list of mod identifiers.

          The following mods are supported:

          - `OptiFine`: adds support for Java properties files used by
            several of its features (`.properties`) and Custom Entity Model
            files (`.jem`, `.jemc`, `.jpm`, and `.jpmc`). It also accepts
            and optimizes vanilla models in the custom item feature files
            directory.

          - `Minecraft Transit Railway 3`: adds support for Blockbench
            modded entity model projects for custom train models
            (`.bbmodel` and `.bbmodelc`) in the `mtr` asset namespace.
        '';

      skip_pack_icon = mkOption types.bool false ''
        Under some circumstances, the `pack.png` pack icon won't be shown
        in the Minecraft UI, even if it is present. Therefore, skipping
        it will save space without any side effects if the pack is to be
        used only under these circumstances. If this option is set to
        `true`, the `pack.png` file that contains the pack icon will not
        be added to the generated ZIP file.

        In most older Minecraft versions, which include 1.16.3 and 1.17.1,
        pack icons are not shown for server resource packs.
      '';

      validate_pack_metadata_file = mkOption types.bool true ''
        This option controls whether the pack metadata file, `pack.mcmeta`,
        will be validated (`true`) or not (`false`). Validating this file
        is a good thing in most circumstances, and you should only disable
        this option if you are extremely concerned about performance, need
        to add a `pack.mcmeta` file to the generated ZIP file later, want
        to use PackSquash with folders that are not a Minecraft pack, or
        similar reasons.

        Even if this option is set to `false`, the `pack.mcmeta` may still
        be validated if
        [`automatic_minecraft_quirks_detection`](#automatic_minecraft_quirks_detection)
        or
        [`automatic_asset_types_mask_detection`](#automatic_asset_types_mask_detection)
        are enabled. To guarantee that the pack metadata file is not
        validated no matter what, both options should be set to `false`.
      '';

      ignore_system_and_hidden_files = mkOption types.bool true ''
        This option controls whether PackSquash will ignore system
        (i.e., whose name signals they were generated by a ubiquitous and
        well-known program that is not related to a Minecraft pack) and
        hidden files (i.e., whose name starts with a dot), not printing
        status messages about them, nor even trying to process them.
        If `true`, these files will be ignored. If `false`, these files
        will not be treated specially and will be processed as normal.
        Ignoring these files is usually a good thing to do unless your
        pack really contains files that are filtered out by this option.
      '';

      zip_spec_conformance_level = mkOption
        (enumStr ["pedantic" "high" "balanced" "disregard"]) "pedantic" ''
          PackSquash uses a custom ZIP compressor that is able to balance
          ZIP file specification conformance and interoperability with
          increased performance, space savings, compressibility, and
          protection against external programs being able to extract files
          from it. This option lets you choose the ZIP specification
          conformance level that is most suitable to your pack and situation.

          The following levels are available:

          - `pedantic`: the generated ZIP files will follow the ZIP file
            specification to the letter, with the objective that they can be
            used with virtually any ZIP file manipulation program. This is a
            safe and user-friendly default, but it has a big downside:
            PackSquash can't do anything that may render the ZIP files it
            generates unconventional. This means that identical files after
            file type-specific optimizations will not be stored only once
            (i.e., deduplicated), the generated ZIP files will not contain
            the metadata needed to reuse them in future runs to speed up
            execution, files will be able to be extracted from them as normal,
            and compressibility of the ZIP file internal structures will
            not be improved. Anyway, you still get file type-specific
            optimizations, Zopfli compression, and metadata removal in both
            the generated ZIP and the pack file, which usually have a big
            impact on pack sizes.

          - `high`: similar to `pedantic`, but it allows storing the metadata
            needed to reuse the generated ZIP files in future PackSquash runs.
            This metadata is stored in a way that is compatible with the vast
            majority of ZIP file manipulation programs, although it
            technically does not conform to the ZIP file specification, so,
            while it is technically possible to find a program that rejects
            the file, in practice that is highly unlikely.

          - `balanced`: like `high`, but enables deduplication of identical
            files in the generated ZIP file. This yields significant space
            savings if somewhat big files are repeated in your pack, like
            textures or sounds, although it also helps with smaller files.
            Some ZIP file manipulation programs will still properly work when
            files are deduplicated, while others will not, so while this has
            a significant impact on interoperability, how that matters to you
            depends on what programs you expect to use with the ZIP file.

          - `disregard`: PackSquash will use every trick up its sleeve to give
            you every feature it offers, including extraction protection and
            improved internal ZIP file structures compressibility, without
            any consideration for interoperability whatsoever. The only
            constraint is that the pack works as usual within Minecraft.

          The following table summarizes and compares what each available conformance
          level offers.

          |                                                                          |   `pedantic`  |       `high`                  |      `balanced`     | `disregard` |
          | :----------------------------------------------------------------------: | :-----------: | :---------------------------: | :-----------------: | :---------: |
          | File type-specific optimizations                                         |       ✔       |               ✔               |          ✔          |      ✔      |
          | Zopfli compression                                                       |       ✔       |               ✔               |          ✔          |      ✔      |
          | Metadata removal<sup>*1</sup>                                            |       ✔       |               ✔               |          ✔          |      ✔      |
          | Identical file deduplication                                             |       ✘       |               ✘               |          ✔          |      ✔      |
          | Extraction protection<sup>*2</sup>                                       |       ✘       |               ✘               |          ✘          |      ✔      |
          | Improved internal ZIP file structures compressibility<sup>*3</sup>       |       ✘       |               ✘               |          ✘          |      ✔      |
          | Programs that can safely manipulate the output ZIP file                  |      Any      | The vast majority of programs |   Select programs   | As few as possible |
          | Potential distribution and storage issues<sup>*4</sup>                   |      None     |              None             |         Some        |  Some more  |
          | Levels whose output ZIP files can be reused with this level<sup>*5</sup> |       —       | `high`, `balanced`  | `high`, `balanced`  | `disregard` |
          | Appropriate for | Using PackSquash for the first time, pack archival and backup, permissively licensed packs, trusting the users of your pack, fostering collaboration and innovation | Similar use cases as `pedantic`, but you want to take advantage of reusing previous ZIP files | Similar use cases as `high`, but you want file deduplication too | Proprietary packs whose usage you want to limit, especially for public server resource packs; just getting the best optimization possible |

          <sup>*1</sup> Metadata removal includes non-critical PNG headers,
          Vorbis comments and ID3 tags, and filesystem metadata such as
          creation time, modification time, permissions, and proprietary user.
          This improves privacy and reduces file sizes.

          <sup>*2</sup>
          > [!IMPORTANT]
          > Due to Minecraft limitations, extraction protection is done using
          > techniques that are not considered secure by modern information
          > security standards (more specifically, they do not hold the
          > [Kerckhoffs's principle](https://en.wikipedia.org/wiki/Kerckhoffs%27s_principle)).
          > In order words, it is not reasonable to expect strong security
          > guarantees from this protection.

          <sup>*3</sup> Compressibility improvements do not reduce the actual
          size of the generated ZIP files. However, they may allow for higher
          savings if the generated ZIP files are compressed again. This is
          useful when serving packs over an HTTP server with static compression
          enabled because it reduces bandwidth requirements, transparently
          compressing and decompressing the pack while it is being downloaded.

          <sup>*4</sup>
          > [!WARNING]
          > *While using progressively higher levels of ZIP specification
          > non-conformance can be effective for optimizing a pack's size and
          > protection, the possibly desirable fact that such generated files
          > are not as easily readable by other programs can backfire in
          > several ways*.
          >
          > Some ways that happened to users are outlined below:
          >
          > - Some hosting services attempt to read uploaded ZIP files for
          >   validation, and if they cannot do so because the ZIP file is
          >   unreadable, the pack may be rejected. For instance,
          >   [mc-packs.net](http://mc-packs.net) is a known-affected hosting
          >   service, whereas Dropbox, AWS S3, Azure Blob Storage, Cloudflare
          >   R2, and most other generic web and file hosting services are
          >   unaffected.
          >
          > - Security software that scans ZIP files may flag such packs as
          >   suspicious because the protection techniques used by PackSquash
          >   can also be exploited by malicious actors in other programs to
          >   bypass security controls. Depending on the security software
          >   configuration, the pack file may be deleted or made unreadable,
          >   causing issues with pack transfer and/or loading. While this
          >   typically isn't a problem for most users, who generally connect
          >   to the Internet through residential ISP gateways and at most run
          >   Windows Defender, some users may have stricter antivirus software,
          >   be connected to networks with enhanced security measures (such as
          >   those in academic or corporate environments, where DPI firewalls,
          >   proxies, and IDS/IPS systems are common), or use services that
          >   perform these checks (e.g., attach the pack to an email whose mail
          >   servers scan attachments with an affected antivirus solution).
          >   See also [issue
          >   #317](https://github.com/ComunidadAylas/PackSquash/issues/317)
          >   for more on this.
          >
          > - Different Minecraft clients handle ZIP specification
          >   non-conformances differently, meaning a pack that works fine on
          >   one client may be rejected by another that has different mods,
          >   is configured differently, or is of a different game version.
          >   While PackSquash usually hides such differences effectively,
          >   and no known Minecraft mods alter the game decompression routines,
          >   there's no guarantee that this will remain the case in the future.
          >
          > - If the original pack files are lost and no backups are available,
          >   recovering the optimized files may be more challenging due to
          >   the difficulty in extracting them reliably.
          >
          > In light of these potential drawbacks, we recommend thoroughly
          > testing and analyzing how lower ZIP specification conformance
          > levels might affect you and your users before deploying packs to
          > production or a wider audience. It's also important to ensure you
          > have the capacity to troubleshoot and address the consequences of
          > the decision you make. For what it's worth, the authors of
          > PackSquash have not found evidence of these negative effects
          > causing widespread problems on several established servers.

          <sup>*5</sup>
          > [!IMPORTANT]
          > In general, *you should be careful when you try to reuse a
          > generated ZIP file to speed up the optimization of a pack if you
          > do any modification to the options file, update PackSquash, move
          > that file between devices, modify it outside of PackSquash, or the
          > set of Minecraft quirks to work around changes*.
          >
          > Failure to follow this advice may lead to the generation of
          > incorrect ZIP files in ways that may not be immediately obvious.
          > Just changing the conformance level to another that is compatible
          > with the level used in the previous run is fine, however. It is
          > also okay to reuse a generated ZIP file as many times as desired if
          > you don't change anything.
          >
          > These are the catches you should keep in mind:
          >
          > - First of all, you may set the
          >   [`never_store_squash_times`](#never_store_squash_times) option
          >   to a value that does not save the metadata needed to reuse ZIP
          >   files, independently of the conformance level. You should not
          >   reuse ZIP files that were generated with this option enabled
          >   (i.e., set to `true`) after you disable it (i.e., set it to
          >   `false`). Doing the opposite thing (i.e., from `false` to `true`)
          >   is fine, but that will end up not reusing the ZIP file.
          >
          > - Any change to an option that affects how files are compressed
          >   or optimized will not be applied for non-modified files because
          >   they will not be processed again.
          >
          > - If the set of [Minecraft quirks](#work_around_minecraft_quirks)
          >   to work around changes, either because PackSquash detects that
          >   the pack was upgraded or downgraded to work with another
          >   Minecraft version or you've explicitly set them to a different
          >   value, the change will not be applied for non-modified files.
          >
          > - PackSquash quickly detects whether a file was modified or not
          >   by looking at the modification timestamp provided by the
          >   filesystem and comparing it with an encrypted timestamp stored
          >   in the ZIP file. The encryption key used is device-specific
          >   (see the documentation on [system
          >   identifiers](https://github.com/ComunidadAylas/PackSquash/wiki/Generated-ZIP-file-reuse-feature-design#system-identifiers)
          >   for more information). If modification timestamps are not
          >   available or reliable, this detection may not work as expected
          >   (this usually is not the case unless you copy files between
          >   partitions or devices, though).
          >
          > - You should not modify otherwise reusable generated ZIP files
          >   outside of PackSquash. Doing so may change the file structure
          >   or timestamp metadata in ways that PackSquash doesn't expect.
          >   You can copy the generated file around and read or extract files
          >   from it.
          >
          > - Some effort is made to make ZIP files generated in the current
          >   version of PackSquash compatible with future versions, but this
          >   compatibility is by no means guaranteed. It is best to start
          >   from scratch after updating PackSquash unless you validate that
          >   the versions are compatible.
          >
          > - Reusing ZIP files that were generated with
          >   [`size_increasing_zip_obfuscation`](#size_increasing_zip_obfuscation)
          >   set to `false` after it is changed to `true`, and vice versa,
          >   is not safe. Trying to do so will, in the best-case scenario,
          >   end up not reusing the ZIP file at all, and in the worst-case
          >   scenario, corrupting data.

          With these gotchas out of the way, to reuse a ZIP file that was
          previously generated by PackSquash, it suffices to set
          [`output_file_path`](#output_file_path) to the path of that file.
          The previous version of the file will be overwritten after the pack
          is processed.
        '';

      size_increasing_zip_obfuscation = mkOption types.bool false ''
        If [`zip_spec_conformance_level`](#zip_spec_conformance_level) is
        set to `disregard`, enabling this option will add more protections
        against inspecting, extracting, or tampering with the generated ZIP
        file that will slightly increase its size. This option does not
        affect whether protections that do not increase the file size are
        added or not and does not have any effect if the conformance level
        does not feature protection.
      '';

      percentage_of_zip_structures_tuned_for_obfuscation_discretion =
        mkOption (types.ints.between 0 100) 0 ''
          If [`zip_spec_conformance_level`](#zip_spec_conformance_level)
          is set to `disregard`, this option sets the approximate
          probability for each internal generated ZIP file structure to
          be stored in a way that favors additional discretion of the fact
          that protection techniques were used, as opposed to a way that
          favors increased compressibility of the result ZIP file. This
          option is ignored for other conformance levels.

          When this option is set to 0 (minimum value), every ZIP record
          will be stored favoring increased compressibility. Conversely,
          when it is set to 100 (maximum value), every ZIP record will be
          stored favoring increased discretion. Other values combine
          increased discretion and compressibility.
        '';

      never_store_squash_times = mkOption types.bool false ''
        This option controls whether PackSquash will refuse to store the
        metadata needed to reuse previously generated ZIP files, and
        likewise not expect such data if the output ZIP file already
        exists, thus not reusing its contents to speed up the process in
        any way, no matter what the
        [`zip_spec_conformance_level`](#zip_spec_conformance_level) is.

        You might want to set this to `true` if you are concerned about
        the presence of encrypted metadata in the generated ZIP files, do
        not care about potential speedups in later runs, file modification
        timestamps are unreliable for some reason, or do not want PackSquash
        to get and use a system ID in any way. In fact, if PackSquash will
        not be run anymore on this pack, it is a good idea to set this to
        `true`, as this improves compressibility a bit and removes the now
        unnecessary metadata.
      '';

      threads = mkOptionNull types.ints.positive ''
        **Default value**: number of available physical CPU threads

        The maximum number of concurrent threads that PackSquash will use
        to process the pack files. Higher numbers can spawn more threads,
        so if your computer has enough physical CPU threads, several files
        can be processed at once, improving the speed substantially.
        However, you might want to use a lower number of threads due to
        memory, power consumption, open file limitations or CPU time
        limitation concerns. This number is tentative, meaning that
        PackSquash may spawn extra threads for internal purposes.
      '';

      spooling_buffers_size = mkOptionNull types.ints.unsigned ''
        **Default value**: half of the available main memory reported by
        the operating system / (number of available physical CPU threads + 1)

        The maximum size of the in-memory buffers that temporarily hold
        data to be written to the generated ZIP file, in MiB. Ideally, if
        the buffers are big enough to hold the entire ZIP file and any
        additional scratch data, PackSquash will work almost entirely in
        memory and not do any disk operation, which is pretty fast. However,
        if some buffer grows bigger than this size threshold, it has to
        be rolled over to disk, which usually is much slower to operate
        with than main memory, because otherwise PackSquash could run out
        of available memory and be forced to abort its execution, which is
        a bad thing. The default value is meant to be an educated guess of
        the optimum value, taking into account the installed physical
        memory (RAM), the size of the pagination file or swap, the amount
        of memory currently used by other applications, that other
        applications may be launched or increase their memory demands while
        PackSquash executes, and the fact that PackSquash uses a buffer for
        each thread that processes packs + one for the generated ZIP file.

        If you run into out-of-memory errors while executing PackSquash,
        try decrementing this value to be able to use it without such
        problems. Conversely, if you observe that PackSquash disk usage
        suddenly rises notably and there is enough available memory to
        spare, try incrementing this value for maximum performance.
      '';

      zip_comment = mkOption types.str "" ''
        The comment string that will be attached to the output ZIP file,
        which is displayed by some ZIP file manipulation programs when
        examining the archive. This string is limited to 65535 US-ASCII
        characters in size, must not contain some special character
        sequences that are internally used by the ZIP format to delimit
        its structures, and is guaranteed to be placed at the end of the
        output ZIP file.

        While it is also possible to attach text notes to a ZIP file by
        adding a file with a well-known name to it, and doing so is
        required for non-text or complex data that takes more than 65535
        characters, comment strings are usually displayed more prominently
        in user interfaces and more convenient for programs to read,
        rendering them more suitable for purposes like storing important
        user-facing notices and file tracking metadata.
      '';

      perFileOptions = lib.mkOption {
        type = types.listOf (types.submodule {
          options = {
            glob = mkOptionNoDefault types.str ''
              This is the file glob that the rest of the options in this
              submodule are applied to.
            '';

            # Audio File Options
            transcode_ogg = mkOption types.bool true ''
              When `true`, Ogg files will be reencoded again to apply
              resampling, channel mixing, pitch shifting, and bitrate
              reduction, which may degrade their quality, but commonly
              saves quite a bit of space. If you change it to `false`,
              Ogg files will be added to the generated ZIP file without
              being reencoded or modified. Non-Ogg audio files will be
              reencoded no matter the value of this option.
            '';

            two_pass_vorbis_optimization_and_validation =
              mkOption types.bool true ''
                When `true`, an additional fast two-pass optimization and
                validation step will be performed on the generated Ogg
                Vorbis file before it is added to the pack, regardless of
                whether it has been transcoded. This enables PackSquash to
                ensure that the audio file will work fine in Minecraft,
                losslessly reduce its size by an average of 5%, and
                optionally obfuscate it to thwart its playback outside of
                Minecraft (see also [`ogg_obfuscation`](#ogg_obfuscation)).

                Due to how fast and unobtrusive this step is, it's usually
                best to leave it enabled. Good reasons to disable it include
                troubleshooting and wanting a slightly faster execution at
                the cost of missing out on the features described above.
            '';

            channels = mkOptionNull types.positive ''
              **Default value**: number of channels of the input audio data

              Specifies the number of audio channels that the processed audio
              file will have in the generated ZIP file. Values different to
              1 (mono) or 2 (stereo) make little sense to use with current
              versions of Minecraft and are not allowed. As per
              [MC-146721](https://bugs.mojang.com/browse/MC-146721),
              Minecraft computes positional sound effects depending on
              whether sounds are mono or stereo, so even though mono sounds
              are more space-efficient (because they contain half the
              samples), downmixing stereo sounds to mono or upmixing mono
              sounds to stereo has side effects.

              It should be noted that, although mono files contain half the
              audio data than stereo ones, this does not necessarily
              translate to half the space savings. The Vorbis codec used
              in Ogg files employs
              [joint encoding](https://en.wikipedia.org/wiki/Joint_encoding),
              which is pretty space-efficient for common sounds.
            '';

            sampling_frequency = mkOptionNull types.ints.positive ''
              **Default value**: `40050` (40.05 kHz) for stereo audio,
              `32000` (32 kHz) for mono audio

              Specifies the sampling frequency (i.e., number of samples per
              second) to which the input audio file will be resampled
              (in Hertz, Hz). If this frequency is higher than the sampling
              frequency of the input audio file, the resampling will be
              skipped to avoid wasting space with redundant samples.

              As per the [Nyquist-Shannon
              theorem](https://en.wikipedia.org/wiki/Nyquist%E2%80%93Shannon_sampling_theorem),
              for a given sampling frequency of 𝑥 Hz, only frequencies up
              to 𝑥 ÷ 2 Hz can be recreated without aliasing artifacts, in
              general. Human speech typically employs frequencies up to
              6 kHz, so a sampling frequency of 12 kHz saves space while
              still providing acceptable audio quality. However, other
              sounds (e.g., music) have a broader frequency spectrum, up
              to 20 kHz (the generally accepted upper limit of the human
              hearing range). Therefore, in any case, a frequency greater
              than 40 kHz is wasteful for encoding audio that will be heard
              by humans and is not meant to be edited any further. The
              default value is meant to sound faithful to vanilla sounds
              that have a wide frequency spectrum while still providing
              significant savings.
            '';

            empty_audio_optimization = mkOption types.bool true ''
              If `true`, empty audio files (i.e., with no audio data, or
              full of complete silence) will be replaced with a special
              empty audio file that is optimized for size and contains no
              audio data. This kind of file works fine in Minecraft and
              most media players, but some may consider the lack of audio
              data an error.

              This option is only honored if the audio file is being
              transcoded, which is always the case when the `transcode_ogg`
              option is set to `true`.
            '';

            bitrate_control_mode = mkOption
              (types.enum ["CQF" "VBR" "ABR" "CABR"]) "CQF" ''
                The bitrate control mode used during transcoding. Different
                bitrate control modes have different tradeoffs between audio
                quality, file size, bandwidth predictability, and encoding
                speed. They also affect how the
                [`target_bitrate_control_metric`](#target_bitrate_control_metric)
                is interpreted, if specified.

                The available bitrate control modes are:

                - `CQF` (Constant Quality Factor): the encoder will interpret
                  the target metric as a quality factor and will try to keep
                  the perceived subjective quality constant at all times.
                  The encoder will have no hard pressures to limit the bitrate
                  in any way, although the quality metric tends to be strongly
                  correlated with an average bitrate for typical signals.

                  - When in doubt, use this mode, as it provides an effective
                    balance for most situations.

                  - The quality factor (i.e., the target metric) is expected
                    to be in the range [-2, 10], where -2 is the worst audio
                    quality, and 10 is the best.

                  - Some advantages of this bitrate control mode include:

                    - It adapts well to different sampling frequencies and
                      channel counts: the encoder knows that it needs fewer bits
                      to encode mono signals than stereo signals of the same
                      quality level, for example.

                    - Unlike with bitrates, it's not possible to ask for
                      unsupported quality levels.

                    - Easy-to-encode audio segments are stored in minimal space,
                      with consistent quality: there is no pressure to meet an
                      average bitrate.

                    - Performance is significantly higher than when using ABR
                      or CABR modes, because the encoder bitrate management engine
                      is not involved.

                  - Some disadvantages of this bitrate control mode include:

                    - The relationship between the quality factor and the actual
                      average bitrate is difficult to predict accurately.

                    - There are no guarantees against difficult to encode
                    segments significantly bumping the average bitrate.

                - `VBR` (Variable BitRate): the encoder will interpret the
                  target metric as an approximate bitrate in kbit/s, internally
                  translating it to a quality factor. Therefore, this mode is
                  equivalent to CQF, but with the quality factor selected in
                  a different way.

                  - Some advantages of this bitrate control mode over
                    CQF include:

                    - The relationship between quality factor and actual
                      average bitrate is easier to predict.

                  - Some disadvantages of this bitrate control mode over
                    CQF include:

                    - The same bitrate may yield different quality levels
                    for different audio signals, or be too high or too low for
                    the quality factors that apply to the signal.

                - `ABR` (Average BitRate): the encoder will interpret the
                  target metric as an average bitrate in kbit/s, and will be
                  coerced to maintain that bitrate for the entire audio signal
                  by using a bitrate management engine. No specific subjective
                  quality level will be targeted.

                  - Some advantages of this bitrate control mode over CQF
                    and VBR include:

                    - The actual average stream bitrate is guaranteed to be
                      very close to the specified average bitrate. Therefore,
                      the resulting file sizes are more predictable.

                    - The maximum instantaneous bitrate for an audio segment
                      can be higher than the average for a small time window,
                      as long as it doesn't affect the long-term average.

                  - Some disadvantages of this bitrate control mode over CQF
                    and VBR include:

                    - Setting too low bitrates for the input signal may
                      severely degrade audio quality, while setting too high
                      bitrates may waste space on padding the data to maintain
                      the average.

                    - Easy-to-encode audio segments may be stored with more
                      bits than necessary for a given quality level in order
                      to maintain the average bitrate. Conversely,
                      harder-to-encode segments may sound worse when the
                      encoder is already outputting at a high bitrate, as it
                      will be deprived of bits to devote to them. The
                      resulting subjective quality will be more inconsistent.

                    - Performance is significantly worse than when using CQF
                      or VBR due to the bitrate management engine being
                      engaged.

                - `CABR` (Constrained Average BitRate): the encoder will
                  interpret the target metric as a hard maximum bitrate and
                  internally select a slightly lower average bitrate than the
                  maximum to maintain. This mode is similar to ABR, but with
                  the addition of a maximum bitrate.

                  - Some advantages of this bitrate control mode over ABR
                    include:

                    - The actual average bitrate is guaranteed to never
                      exceed the specified maximum bitrate, which limits
                      the maximum file size with certainty.

                  - Some disadvantages of this bitrate control mode over
                    ABR include:

                    - To ensure that the hard maximum bitrate is never
                      exceeded, a lower average bitrate will be targeted,
                      which provides headroom for hard-to-encode segments,
                      but usually results in inferior quality.

                Because the default value of `target_bitrate_control_metric`
                is a quality factor, specifying it when selecting a bitrate
                control mode other than `CQF` is required.
              '';

            target_bitrate_control_metric =
              mkOptionNull types.numbers.nonnegative ''
                **Default value**: `0.25` (quality factor, ≈68 kbit/s at
                44.1 kHz) for stereo audio, `0.0` (quality factor) for mono
                audio

                The metric to use as a target for the specified bitrate
                control mode when transcoding. Depending on the
                [selected bitrate control mode](#bitrate_control_mode),
                this will be interpreted as a quality factor, average
                bitrate, approximate bitrate, or maximum bitrate.
              '';
          };
        });

        default = [];

        description = ''
          PackSquash supports customizing how several pack file types are
          compressed, on a per-file basis, via
          [tables](https://toml.io/en/v1.0.0#table). Tables represent
          a group of options that are applied to the files whose relative
          path matches a
          [extended glob pattern syntax](https://docs.rs/globset/0.4.8/globset/index.html#syntax)
          contained in the table name.

          For matching, the path component separator is normalized to a
          forward slash (/), so the configuration files are operating
          system agnostic. Also, the `*` and `?` metacharacters can never
          match a path separator. The backslash character may be used to
          escape special characters.

          For example, you can match any files inside a "music" or "ambience"
          folder that have a non-empty name and an audio file extension with
          the following pattern:

          ```glob
          **/{music,ambience}/?*.{og[ga],mp3,wav,flac}
          ```

          Another example that matches the same files as before, but only
          when they are in the "music" or "ambience" folders of a resource
          pack assets folder is:

          ```glob
          assets/*/sounds/{music,ambience}/?*.{og[ga],mp3,wav,flac}
          ```

          Keep in mind that if your pattern contains a dot or characters
          that are not ASCII letters, ASCII digits, underscores, and dashes
          (A-Za-z0-9_-), you will need to put them in a string (i.e.,
          between single quotes, like `'this'`) when writing the table name
          in the options file.

          Of course, different file types require different options.
          PackSquash will detect on the fly the file type the configuration
          you write is intended for. If several patterns match a single file,
          PackSquash will use the first one that customizes options
          appropriate for the file type, and if no pattern is appropriate or
          no pattern matches, use default options. There is a list of options
          you can change per file type below.
        '';
      };
    };
  };
in
  null
