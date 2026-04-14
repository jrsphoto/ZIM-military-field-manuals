# US Military Field Manuals - Offline Archive

A self-hosted offline reference collection of US military field manuals, built for use with [Kiwix](https://kiwix.org). Part of Project Nomad.

## What This Is

This project packages ~180 public domain military field manuals (Army, USMC, Navy, Air Force, and joint publications) into a ZIM file that can be served locally via Kiwix. The source documents come from the [Internet Archive military field manuals collection](https://archive.org/details/military-field-manuals-and-guides).

The web interface has search, branch filtering, and a VIEW button for each document.

![Field Manual Archive UI](Screenshot.png)

## Directory Structure

```
Field Manuals/
  install.sh              # downloads PDFs, builds the ZIM, and optionally deploys
  html/
    index.html            # the web interface
    illustration.png      # 48x48 icon required by zimwriterfs
    pdfs/                 # PDFs are downloaded here (not tracked by git)
```

## Setup

This should be run directly on the machine hosting the Kiwix/Nomad server.

### 1. Install Dependencies

```bash
sudo apt install wget unzip python3 zim-tools
```

### 2. Clone the Repo

```bash
git clone https://github.com/jrsphoto/ZIM-military-field-manuals.git
cd ZIM-military-field-manuals
chmod +x install.sh
```

### 3. Run the Installer

The simplest way is to let the script handle everything in one shot:

```bash
./install.sh \
  --deploy \
  --zim-dest=/your/kiwix/library \
  --container=your_kiwix_container
```

This will:
- Download the full PDF collection from archive.org as a single zip (~7GB -- expect it to take a while)
- Extract all PDFs into `html/pdfs/`
- Build `field_manuals.zim` in the current directory
- Copy the ZIM to your Kiwix library directory with correct ownership
- Register it with the Kiwix library XML
- Restart the Kiwix container

If the download gets interrupted just re-run -- wget will resume where it left off and the script will offer to reuse the partial zip.

## Script Options

| Option | Description |
|--------|-------------|
| `--skip-download` | Skip the PDF download, use existing files in `html/pdfs/` |
| `--skip-zim` | Skip the ZIM build, just download the PDFs |
| `--deploy` | Automatically deploy to Kiwix after building (requires `--zim-dest` and `--container`) |
| `--zim-dest=PATH` | Path to your Kiwix library directory on the host |
| `--container=NAME` | Name of your Kiwix Docker container |

## Rebuilding

If you update `index.html` or add more PDFs, re-run with `--skip-download` and `--deploy`:

```bash
./install.sh --skip-download \
  --deploy \
  --zim-dest=/your/kiwix/library \
  --container=your_kiwix_container
```

The script will remove any existing entries for this ZIM from the Kiwix library before re-adding the new one, so no duplicates build up over time.

## Dependencies

- `wget` -- downloads the PDF collection
- `unzip` -- extracts the downloaded zip
- `python3` -- generates the illustration.png icon if missing
- `zimwriterfs` -- part of the `zim-tools` package
- Docker with a running Kiwix container

## Future Enhancements

- **Remote deployment** -- add options to `install.sh` to SCP the ZIM file to a remote Nomad host, automatically register it with the Kiwix library XML, and restart the Kiwix container. Needs to handle sudo for writing to protected directories, SSH key auth, and local vs remote command differences.

## Source

All documents are public domain US government publications sourced from:
https://archive.org/details/military-field-manuals-and-guides
