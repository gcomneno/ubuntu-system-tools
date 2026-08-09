# Linux release package

[English] | [Italiano](linux-release-package.it.md)

Official release packages are published for **Linux only**.

For v0.3.0 the release assets are:

- `ubuntu-system-tools-v0.3.0-linux.tar.gz`
- `ubuntu-system-tools-v0.3.0-linux.tar.gz.sha256`

The archive is architecture-neutral: it contains the repository's shell/Python utilities as executable files rather than compiled binaries.

## Verify the download

Keep the archive and checksum file in the same directory, then run:

```bash
sha256sum -c ubuntu-system-tools-v0.3.0-linux.tar.gz.sha256
```

Do not install an archive whose checksum does not verify.

## Extract

```bash
tar -xzf ubuntu-system-tools-v0.3.0-linux.tar.gz
cd ubuntu-system-tools-v0.3.0-linux
```

## User-local installation

The default prefix is `~/.local`, so tools are copied to `~/.local/bin`:

```bash
./install.sh
```

The release installer uses **autonomous executable copies**. It does not create links back to the extracted package.

If `~/.local/bin` is not already in your `PATH`, add it through your normal shell configuration.

## Custom prefix

Use an absolute path:

```bash
./install.sh --prefix "$HOME/tools"
```

For a system-wide installation, privilege escalation must remain explicit and external to the installer:

```bash
sudo ./install.sh --prefix /usr/local
```

`install.sh` never invokes `sudo` itself.

## Existing files and `--force`

Before copying anything, the installer preflights every destination.

- identical regular files are accepted;
- divergent files and symlinks are refused;
- no partial installation is performed when preflight fails;
- `--force` is available only for a destination you have explicitly reviewed.

```bash
./install.sh --force
```

## Dependencies

The package does **not** install operating-system or Python dependencies automatically. Each tool keeps the same dependency contract documented by the repository.

Examples include Calibre for real ebook conversion, CUPS for printer diagnostics, and `faster-whisper` for audio transcription.

## Uninstall

The installer records a SHA-256 manifest under the selected prefix and installs a versioned safe uninstaller.

For the default prefix:

```bash
~/.local/share/ubuntu-system-tools/uninstall-v0.3.0.sh
```

For a custom prefix:

```bash
/path/to/prefix/share/ubuntu-system-tools/uninstall-v0.3.0.sh --prefix /path/to/prefix
```

The uninstaller preflights every installed tool before removing anything. If an installed tool has changed since installation, removal is refused unless you explicitly pass `--force` after review.

## Build the package from source

On Linux:

```bash
make package-linux VERSION=v0.3.0
```

The default output directory is `dist/`. The builder emits both the `.tar.gz` archive and its `.sha256` file. Repeated builds from the same source tree are byte-identical.

## Not provided in v0.3.0

The v0.3.0 release intentionally does not publish:

- Windows packages;
- macOS packages;
- `.deb` packages;
- Snap packages;
- Flatpak packages;
- AppImages.
