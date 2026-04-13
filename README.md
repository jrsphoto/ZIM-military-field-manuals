# US Military Field Manuals - Offline Archive

A self-hosted offline reference collection of US military field manuals, built for use with [Kiwix](https://kiwix.org). Part of Project Nomad.

## What This Is

This project packages ~180 public domain military field manuals (Army, USMC, Navy, Air Force, and joint publications) into a ZIM file that can be served locally via Kiwix. The source documents come from the [Internet Archive military field manuals collection](https://archive.org/details/military-field-manuals-and-guides).

The web interface has search, branch filtering, and VIEW/DOWNLOAD buttons for each document.

## Directory Structure

```
Field Manuals/
  build_zim.sh            # builds the .zim file
  download_manuals.sh     # downloads all PDFs from archive.org
  html/
    index.html            # the web interface
    illustration.png      # 48x48 icon required by zimwriterfs
    pdfs/                 # downloaded PDF files go here
```

## Setup

### 1. Download the PDFs

```bash
chmod +x download_manuals.sh
./download_manuals.sh
```

This downloads all PDFs into `html/pdfs/`. It will skip files that already exist so it's safe to re-run if something fails. Expect it to take a while -- there's about 7GB of material.

### 2. Update the Base URL

Before building the ZIM, open `html/index.html` and change the `BASE` constant near the bottom of the file from the archive.org URL to the local path:

```javascript
const BASE = './pdfs/';
```

### 3. Build the ZIM

```bash
chmod +x build_zim.sh
./build_zim.sh
```

Output will be `field_manuals.zim` in this directory. Takes several minutes depending on your hardware.

### 4. Deploy to Kiwix

Copy the ZIM to your Kiwix library folder:

```bash
cp field_manuals.zim /opt/project-nomad/storage/zim/
```

Register it with the Kiwix library (required -- Kiwix won't pick it up automatically):

```bash
docker exec nomad_kiwix_server kiwix-manage \
  /data/kiwix-library.xml add \
  /data/field_manuals.zim
```

Then restart the container:

```bash
docker restart nomad_kiwix_server
```

## Rebuilding

If you add more PDFs or change the HTML, just run `build_zim.sh` again and repeat the deploy steps. The script will remove the old ZIM before building the new one.

## Dependencies

- `wget` -- for the download script
- `zimwriterfs` -- part of the `zim-tools` package
- `python3` -- used by the download script to decode filenames
- Docker with a running Kiwix container

Install zim-tools if you don't have it:

```bash
sudo apt install zim-tools
```

## Source

All documents are public domain US government publications sourced from:
https://archive.org/details/military-field-manuals-and-guides
