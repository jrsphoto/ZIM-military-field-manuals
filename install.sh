#!/usr/bin/env bash
# =============================================================================
# install.sh
# Installer for the US Military Field Manuals offline archive.
#
# This script will:
#   1. Check dependencies
#   2. Download all PDFs from archive.org as a single zip
#   3. Extract PDFs into html/pdfs/
#   4. Build the ZIM file
#   5. Print deployment instructions
#
# Place this script in the "Field Manuals" root folder alongside html/.
#
# Usage:
#   chmod +x install.sh
#   ./install.sh
#
# To skip the download (if you already have the PDFs):
#   ./install.sh --skip-download
#
# To skip the ZIM build (just download the PDFs):
#   ./install.sh --skip-zim
#
# To automatically deploy to a local Kiwix container after building:
#   ./install.sh --deploy --zim-dest /path/to/kiwix/library --container nomad_kiwix_server
#
# All options can be combined:
#   ./install.sh --skip-download --deploy --zim-dest /opt/project-nomad/storage/zim --container nomad_kiwix_server
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HTML_DIR="${SCRIPT_DIR}/html"
PDF_DIR="${HTML_DIR}/pdfs"
ZIM_OUT="${SCRIPT_DIR}/field_manuals.zim"
TMP_ZIP="${SCRIPT_DIR}/manuals_download.zip"

ARCHIVE_URL="https://archive.org/compress/military-field-manuals-and-guides/formats=TEXT%20PDF,IMAGE%20CONTAINER%20PDF,ITEM%20TILE,ARCHIVE%20BITTORRENT,METADATA"

SKIP_DOWNLOAD=0
SKIP_ZIM=0
DEPLOY=0
ZIM_DEST=""
CONTAINER=""

for arg in "$@"; do
  case $arg in
    --skip-download)   SKIP_DOWNLOAD=1 ;;
    --skip-zim)        SKIP_ZIM=1 ;;
    --deploy)          DEPLOY=1 ;;
    --zim-dest=*)      ZIM_DEST="${arg#*=}" ;;
    --container=*)     CONTAINER="${arg#*=}" ;;
    *)                 echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

# Validate deploy arguments
if [[ $DEPLOY -eq 1 ]]; then
  if [[ -z "$ZIM_DEST" ]]; then
    echo -e "${RED}[ERROR]${NC} --deploy requires --zim-dest=/path/to/kiwix/library"
    exit 1
  fi
  if [[ -z "$CONTAINER" ]]; then
    echo -e "${RED}[ERROR]${NC} --deploy requires --container=<container_name>"
    exit 1
  fi
fi

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
CYN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

banner() {
  echo -e "${YLW}"
  echo "  ╔══════════════════════════════════════════════════════════════╗"
  echo "  ║        FIELD MANUAL ARCHIVE -- INSTALLER                     ║"
  echo "  ║        PROJECT NOMAD // KIWIX OFFLINE SYSTEM                 ║"
  echo "  ╚══════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

check_deps() {
  echo -e "${BOLD}Checking dependencies...${NC}"
  local missing=0

  for cmd in wget unzip python3; do
    if command -v "$cmd" &>/dev/null; then
      echo -e "  ${GRN}[OK]${NC}  $cmd"
    else
      echo -e "  ${RED}[MISSING]${NC}  $cmd"
      missing=1
    fi
  done

  if [[ $SKIP_ZIM -eq 0 ]]; then
    if command -v zimwriterfs &>/dev/null; then
      echo -e "  ${GRN}[OK]${NC}  zimwriterfs ($(zimwriterfs --version 2>&1 | head -1))"
    else
      echo -e "  ${RED}[MISSING]${NC}  zimwriterfs"
      echo -e "             Install with: sudo apt install zim-tools"
      missing=1
    fi
  fi

  if [[ $missing -eq 1 ]]; then
    echo ""
    echo -e "${RED}[ERROR]${NC} Missing dependencies. Install them and re-run."
    exit 1
  fi
  echo ""
}

download_pdfs() {
  echo -e "${BOLD}Step 1: Downloading PDF collection from archive.org${NC}"
  echo -e "  ${CYN}URL:${NC} ${ARCHIVE_URL}"
  echo ""
  echo -e "  This is a large download (~7GB compressed). This will take a"
  echo -e "  while depending on your connection speed."
  echo ""

  mkdir -p "$PDF_DIR"

  if [[ -f "$TMP_ZIP" ]]; then
    echo -e "  ${YLW}[INFO]${NC}  Found existing download at ${TMP_ZIP}"
    read -rp "  Re-use it? [Y/n]: " reuse
    reuse="${reuse:-Y}"
    if [[ "$reuse" =~ ^[Nn]$ ]]; then
      rm -f "$TMP_ZIP"
    fi
  fi

  if [[ ! -f "$TMP_ZIP" ]]; then
    echo -e "  ${YLW}[GET]${NC}   Downloading zip..."
    wget \
      --progress=bar:force \
      --tries=3 \
      --timeout=300 \
      --waitretry=30 \
      --continue \
      --user-agent="Mozilla/5.0 (compatible; personal-archive-downloader)" \
      -O "$TMP_ZIP" \
      "$ARCHIVE_URL"
    echo ""
  fi

  echo -e "  ${YLW}[INFO]${NC}  Extracting PDFs to ${PDF_DIR}..."
  echo ""

  # Extract only PDF files, flatten any subdirectory structure into pdf_dir
  unzip -o -j "$TMP_ZIP" "*.pdf" -d "$PDF_DIR" 2>&1 | \
    grep -E "inflating|extracting" | \
    awk '{print "  extracting: " $NF}' || true

  PDF_COUNT=$(find "$PDF_DIR" -name "*.pdf" | wc -l)
  echo ""
  echo -e "  ${GRN}[OK]${NC}   ${PDF_COUNT} PDFs extracted to ${PDF_DIR}"
  echo ""

  # Clean up zip to save space
  read -rp "  Delete the downloaded zip file to save disk space? [Y/n]: " cleanup
  cleanup="${cleanup:-Y}"
  if [[ ! "$cleanup" =~ ^[Nn]$ ]]; then
    rm -f "$TMP_ZIP"
    echo -e "  ${YLW}[INFO]${NC}  Zip removed."
  fi
  echo ""
}

build_zim() {
  echo -e "${BOLD}Step 2: Building ZIM file${NC}"

  if [[ ! -f "${HTML_DIR}/index.html" ]]; then
    echo -e "  ${RED}[ERROR]${NC}  index.html not found at ${HTML_DIR}/index.html"
    exit 1
  fi

  if [[ ! -f "${HTML_DIR}/assets/illustration.png" ]]; then
    echo -e "  ${YLW}[INFO]${NC}  assets/illustration.png not found -- generating one..."
    mkdir -p "${HTML_DIR}/assets"
    python3 -c "
import struct, zlib

def png48(r, g, b):
    raw = bytes([0] + [r, g, b] * 48) * 48
    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(c[4:]) & 0xffffffff)
    data  = chunk(b'IHDR', struct.pack('>IIBBBBB', 48, 48, 8, 2, 0, 0, 0))
    data += chunk(b'IDAT', zlib.compress(raw))
    data += chunk(b'IEND', b'')
    return b'\x89PNG\r\n\x1a\n' + data

open('${HTML_DIR}/assets/illustration.png', 'wb').write(png48(74, 82, 64))
print('  assets/illustration.png created')
"
  fi

  PDF_COUNT=$(find "$PDF_DIR" -name "*.pdf" 2>/dev/null | wc -l)
  echo -e "  ${CYN}Source:${NC}  ${HTML_DIR}"
  echo -e "  ${CYN}Output:${NC}  ${ZIM_OUT}"
  echo -e "  ${CYN}PDFs:${NC}    ${PDF_COUNT} files"
  echo ""

  if [[ -f "$ZIM_OUT" ]]; then
    echo -e "  ${YLW}[INFO]${NC}  Removing existing $(basename "$ZIM_OUT")..."
    rm -f "$ZIM_OUT"
  fi

  echo -e "  ${YLW}[INFO]${NC}  Running zimwriterfs -- this will take several minutes..."
  echo "────────────────────────────────────────────────────────────────"

  zimwriterfs \
    --welcome=index.html \
    --illustration=assets/illustration.png \
    --language=eng \
    --name="field_manuals" \
    --title="US Military Field Manuals" \
    --description="US Army, USMC, Navy & Joint Field Manuals" \
    --longDescription="A collection of ~180 US military field manuals covering tactics, survival, navigation, engineering, intelligence, special operations and more. Sourced from the Internet Archive." \
    --creator="US Government" \
    --publisher="ProjectNomad" \
    --tags="_category:military;military;_ftindex:yes" \
    --verbose \
    "$HTML_DIR" \
    "$ZIM_OUT"

  echo "────────────────────────────────────────────────────────────────"
  echo ""

  if [[ -f "$ZIM_OUT" ]]; then
    SIZE=$(du -sh "$ZIM_OUT" | cut -f1)
    echo -e "  ${GRN}[OK]${NC}  ZIM created: $(basename "$ZIM_OUT") (${SIZE})"
  else
    echo -e "  ${RED}[ERROR]${NC}  ZIM file not found after build."
    exit 1
  fi
  echo ""
}

deploy_instructions() {
  echo -e "${BOLD}Done. To deploy to Kiwix:${NC}"
  echo ""
  echo    "  1. Copy the ZIM file to your Kiwix library directory:"
  echo    "     cp field_manuals.zim /your/kiwix/library/"
  echo ""
  echo    "  2. Set correct ownership (use the container's uid):"
  echo    "     KIWIX_UID=\$(sudo docker exec <kiwix_container> id -u)"
  echo    "     sudo chown \$KIWIX_UID:\$KIWIX_UID /your/kiwix/library/field_manuals.zim"
  echo    "     sudo chown \$KIWIX_UID:\$KIWIX_UID /your/kiwix/library/kiwix-library.xml"
  echo ""
  echo    "  3. Register with Kiwix:"
  echo    "     sudo docker exec -u \$KIWIX_UID <kiwix_container> kiwix-manage \\"
  echo    "       /data/kiwix-library.xml add \\"
  echo    "       /data/field_manuals.zim"
  echo ""
  echo    "  4. Restart the Kiwix container:"
  echo    "     sudo docker restart <kiwix_container>"
  echo ""
  echo    "  Or run this script with --deploy to do all of the above automatically:"
  echo    "     ./install.sh --skip-download --deploy \\"
  echo    "       --zim-dest=/your/kiwix/library \\"
  echo    "       --container=<kiwix_container>"
  echo ""
}

deploy() {
  local zim_name
  zim_name=$(basename "$ZIM_OUT")
  local dest_zim="${ZIM_DEST}/${zim_name}"
  local dest_xml="${ZIM_DEST}/kiwix-library.xml"

  echo -e "${BOLD}Step 3: Deploying to Kiwix${NC}"
  echo -e "  ${CYN}Container :${NC} ${CONTAINER}"
  echo -e "  ${CYN}Library   :${NC} ${ZIM_DEST}"
  echo ""

  # Check container is running
  if ! sudo docker inspect "$CONTAINER" &>/dev/null; then
    echo -e "  ${RED}[ERROR]${NC}  Container '${CONTAINER}' not found."
    exit 1
  fi

  # Get the uid the container runs as
  KIWIX_UID=$(sudo docker exec "$CONTAINER" id -u)
  echo -e "  ${YLW}[INFO]${NC}  Container runs as uid ${KIWIX_UID}"

  # Copy ZIM to destination
  echo -e "  ${YLW}[INFO]${NC}  Copying $(basename "$ZIM_OUT") to ${ZIM_DEST}..."
  sudo cp "$ZIM_OUT" "$dest_zim"

  # Fix ownership on ZIM and library XML
  echo -e "  ${YLW}[INFO]${NC}  Setting ownership to ${KIWIX_UID}:${KIWIX_UID}..."
  sudo chown "${KIWIX_UID}:${KIWIX_UID}" "$dest_zim"
  if [[ -f "$dest_xml" ]]; then
    sudo chown "${KIWIX_UID}:${KIWIX_UID}" "$dest_xml"
  fi

  # Remove ALL existing entries pointing at this ZIM file (handles duplicates from repeated deploys)
  echo -e "  ${YLW}[INFO]${NC}  Removing any existing entries for ${zim_name} from Kiwix library..."
  while true; do
    EXISTING_ID=$(sudo docker exec -u "$KIWIX_UID" "$CONTAINER" \
      kiwix-manage /data/kiwix-library.xml show 2>/dev/null | \
      grep -B5 "path:.*${zim_name}" | grep "^id:" | head -1 | awk '{print $2}' || true)

    if [[ -z "$EXISTING_ID" ]]; then
      break
    fi

    sudo docker exec -u "$KIWIX_UID" "$CONTAINER" \
      kiwix-manage /data/kiwix-library.xml remove "$EXISTING_ID"
    echo -e "  ${YLW}[INFO]${NC}  Removed entry: ${EXISTING_ID}"
  done

  # Add new ZIM to library
  echo -e "  ${YLW}[INFO]${NC}  Registering with Kiwix library..."
  sudo docker exec -u "$KIWIX_UID" "$CONTAINER" \
    kiwix-manage /data/kiwix-library.xml add "/data/${zim_name}"

  # Restart container
  echo -e "  ${YLW}[INFO]${NC}  Restarting ${CONTAINER}..."
  sudo docker restart "$CONTAINER"

  echo ""
  echo -e "  ${GRN}[OK]${NC}  Deployment complete. Kiwix is restarting."
  echo ""
}

# =============================================================================
banner
check_deps

if [[ $SKIP_DOWNLOAD -eq 0 ]]; then
  download_pdfs
else
  echo -e "${YLW}[INFO]${NC}  Skipping download (--skip-download)."
  echo ""
fi

if [[ $SKIP_ZIM -eq 0 ]]; then
  build_zim
else
  echo -e "${YLW}[INFO]${NC}  Skipping ZIM build (--skip-zim)."
  echo ""
fi

if [[ $DEPLOY -eq 1 ]]; then
  deploy
else
  deploy_instructions
fi
