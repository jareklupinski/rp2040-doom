#!/usr/bin/env bash
# Unified build script for RP2040 / RP2350 (Pico / Pico2)
#
# Usage:
#   ./build.sh                # auto-detect board (needs device in BOOTSEL for detection) or defaults to pico2
#   ./build.sh pico2          # force pico2
#   ./build.sh pico           # force original pico (RP2040)
#   ./build.sh vgaboard       # legacy RP2040 VGA board definition
#   BUILD_DIR=custom ./build.sh pico2   # override build directory name
#
# Environment (required): PICO_SDK_PATH, PICO_EXTRAS_PATH
# Optional: CMAKE_BUILD_TYPE (defaults to MinSizeRel)

set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
	grep '^#' "$0" | sed 's/^# \{0,1\}//'
	exit 0
fi

# Directory of this script (absolute). Use this when auto-detecting relative locations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Parse arguments ----
USER_BOARD="${1:-}"  # user-provided override
BUILD_AND_FLASH_ST7789=true

# ---- Detect / select board ----
BOARD=""

detect_board() {
	# Try to detect RP2350 vs RP2040 if a device is in BOOTSEL mode
	if command -v picotool >/dev/null 2>&1; then
		if picotool info -d >/dev/null 2>&1; then
			if picotool info -d 2>/dev/null | grep -q 'RP2350'; then
				echo "pico2"
				return 0
			fi
			# If we explicitly see RP2040 we prefer pico
			if picotool info -d 2>/dev/null | grep -q 'RP2040'; then
				echo "pico"
				return 0
			fi
		fi
	fi
	# Fallback default: prefer pico2 (newer) unless user overrides
	echo "pico2"
}

if [[ -n "$USER_BOARD" ]]; then
	BOARD="$USER_BOARD"
else
	BOARD="$(detect_board)"
fi

echo "[build.sh] Using PICO_BOARD=${BOARD}" >&2

# ---- Auto / validate environment ----
# Allow the script to auto-populate common locations if vars are unset
if [[ -z "${PICO_SDK_PATH:-}" ]]; then
	if [[ -d "${SCRIPT_DIR}/pico/pico-sdk" ]]; then
		export PICO_SDK_PATH="${SCRIPT_DIR}/pico/pico-sdk"
		echo "[build.sh] Auto-detected PICO_SDK_PATH=$PICO_SDK_PATH" >&2
	fi
fi
if [[ -z "${PICO_EXTRAS_PATH:-}" ]]; then
	if [[ -d "${SCRIPT_DIR}/pico/pico-extras" ]]; then
		export PICO_EXTRAS_PATH="${SCRIPT_DIR}/pico/pico-extras"
		echo "[build.sh] Auto-detected PICO_EXTRAS_PATH=$PICO_EXTRAS_PATH" >&2
	fi
fi

if [[ -z "${PICO_SDK_PATH:-}" ]]; then
	echo "[build.sh] ERROR: PICO_SDK_PATH not set and not found at ~/pico/pico-sdk" >&2
	echo "           Set it: export PICO_SDK_PATH=~/pico/pico-sdk" >&2
	exit 1
fi
if [[ ! -d "$PICO_SDK_PATH" ]]; then
	echo "[build.sh] ERROR: PICO_SDK_PATH directory does not exist: $PICO_SDK_PATH" >&2
	exit 1
fi
if [[ -z "${PICO_EXTRAS_PATH:-}" ]]; then
	echo "[build.sh] WARNING: PICO_EXTRAS_PATH not set (optional, but recommended)." >&2
else
	if [[ ! -d "$PICO_EXTRAS_PATH" ]]; then
		echo "[build.sh] WARNING: PICO_EXTRAS_PATH directory does not exist: $PICO_EXTRAS_PATH" >&2
	fi
fi

# ---- Toolchain (user-requested default) ----
# Allow override via existing env; otherwise set to the provided absolute path.
# pico-sdk will look for the cross tools in "$PICO_TOOLCHAIN_PATH/bin" if set.
: "${PICO_TOOLCHAIN_PATH:=./arm-toolchain/arm-gnu-toolchain-13.2.Rel1-darwin-arm64-arm-none-eabi}"
if [[ ! -d "$PICO_TOOLCHAIN_PATH" ]]; then
	echo "[build.sh] ERROR: PICO_TOOLCHAIN_PATH directory not found: $PICO_TOOLCHAIN_PATH" >&2
	exit 1
fi
echo "[build.sh] Using PICO_TOOLCHAIN_PATH=$PICO_TOOLCHAIN_PATH" >&2
export PICO_TOOLCHAIN_PATH

# If PICO_TOOLCHAIN_PATH is relative, make it absolute relative to the script dir
if [[ "$PICO_TOOLCHAIN_PATH" != /* ]]; then
	PICO_TOOLCHAIN_PATH="${SCRIPT_DIR}/${PICO_TOOLCHAIN_PATH}"
	export PICO_TOOLCHAIN_PATH
	echo "[build.sh] Normalized PICO_TOOLCHAIN_PATH to absolute: $PICO_TOOLCHAIN_PATH" >&2
fi

# Ensure toolchain bin (and its make) are at front of PATH so CMake picks correct tools
TOOLCHAIN_BIN="$PICO_TOOLCHAIN_PATH/bin"
if [[ -d "$TOOLCHAIN_BIN" ]]; then
	case ":$PATH:" in
		*":$TOOLCHAIN_BIN:"*) ;; # already there
		*) export PATH="$TOOLCHAIN_BIN:$PATH"; echo "[build.sh] Added $TOOLCHAIN_BIN to PATH" >&2 ;;
	esac
else
	echo "[build.sh] WARNING: Toolchain bin directory missing: $TOOLCHAIN_BIN" >&2
fi

CMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-MinSizeRel}"

# ---- Build directory ----
DEFAULT_BUILD_DIR="${BOARD}-build"
BUILD_DIR="${BUILD_DIR:-$DEFAULT_BUILD_DIR}"

echo "[build.sh] Build directory: ${BUILD_DIR}" >&2

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

set -x
cmake -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE}" \
			-DPICO_BOARD="${BOARD}" \
			-DPICO_SDK_PATH="${PICO_SDK_PATH}" \
			-DPICO_EXTRAS_PATH="${PICO_EXTRAS_PATH}" \
			..
set +x

echo "[build.sh] Configuration complete. Example build command:" >&2
echo "[build.sh]   make -j" >&2
echo "[build.sh] Or to build only the BSP ST7789 target for RP2350-Touch-LCD-2.8:" >&2
echo "[build.sh]   make -j doom_tiny_usb_ST7789_240_135" >&2
echo "[build.sh]" >&2
echo "[build.sh] To build and flash ST7789 BSP target:" >&2
echo "[build.sh]   ./build.sh pico2 --build-and-flash-st7789" >&2

# ---- Build and flash ST7789 target if requested ----
if [[ "$BUILD_AND_FLASH_ST7789" == "true" ]]; then
	echo "[build.sh] Building ST7789 BSP target for RP2350-Touch-LCD-2.8..." >&2
	make -j doom_tiny_usb_ST7789_240_135
	
	if [[ $? -eq 0 ]]; then
		echo "[build.sh] Build successful! Attempting to flash..." >&2
		UF2_FILE="src/doom_tiny_usb_ST7789_240_135.uf2"
		
		if [[ -f "$UF2_FILE" ]]; then
			echo "[build.sh] Found UF2 file: $UF2_FILE" >&2
			
			# Check if picotool is available for flashing
			if command -v picotool >/dev/null 2>&1; then
			# Function to check if device is in bootsel mode
			check_bootsel_device() {
				# In bootsel mode, picotool info -d should work and show device info
				picotool info -d >/dev/null 2>&1
			}
			
			# Function to check if device is running (not in bootsel)
			check_running_device() {
				# When running, picotool info (without -d) should work and show program info
				if picotool info >/dev/null 2>&1; then
					# Additional check: make sure it shows "Program Information" (running mode)
					picotool info 2>/dev/null | grep -q "Program Information"
				else
					return 1
				fi
			}				# Check if device is already running and offer to reboot to bootsel
				if check_running_device; then
					echo "[build.sh] ✓ Found running RP2040/RP2350 device" >&2
				fi
				
				# Try to detect device in bootsel mode
				echo "[build.sh] Checking for device in BOOTSEL mode..." >&2
				while ! check_bootsel_device; do
					echo "" >&2
					echo "[build.sh] ⚠️  No RP2040/RP2350 device found in BOOTSEL mode!" >&2
					echo "[build.sh] Please:" >&2
					echo "[build.sh]   1. Hold BOOTSEL button while connecting USB, OR" >&2
					echo "[build.sh]   2. Hold BOOTSEL button and press RESET" >&2
					echo "[build.sh] Then press ENTER to check again..." >&2
					read -r
					echo "[build.sh] Checking again..." >&2
				done
				
				echo "[build.sh] ✓ Device found in BOOTSEL mode!" >&2
				echo "[build.sh] Attempting to flash using picotool..." >&2
				if picotool load "$UF2_FILE" -v; then
					echo "[build.sh] ✓ Successfully flashed $UF2_FILE" >&2
					
					# Also flash the WHX game data file
					# WHX_FILE="../doom.whd"
					# if [[ -f "$WHX_FILE" ]]; then
					# 	echo "[build.sh] Flashing WHX game data file..." >&2
					# 	if picotool load -t bin "$WHX_FILE" -o 0x10042000 -v; then
					# 		echo "[build.sh] ✓ Successfully flashed $WHX_FILE at 0x10042000" >&2
					# 	else
					# 		echo "[build.sh] ⚠️  Failed to flash WHX file, but firmware was flashed successfully" >&2
					# 	fi
					# else
					# 	echo "[build.sh] ⚠️  WHX file not found at $WHX_FILE" >&2
					# fi
					
					# Reboot the device automatically
					echo "[build.sh] Rebooting device..." >&2
					sleep 1
					picotool reboot
					echo "[build.sh] ✓ Device rebooted and running new firmware!" >&2
				else
					echo "[build.sh] ❌ Failed to flash with picotool" >&2
					exit 1
				fi
			else
				# Look for mounted RPI-RP2 device
				if [[ -d "/Volumes/RPI-RP2" ]]; then
					echo "[build.sh] Found RPI-RP2 drive, copying UF2 file..." >&2
					cp "$UF2_FILE" "/Volumes/RPI-RP2/"
					echo "[build.sh] ✓ Successfully copied $UF2_FILE to /Volumes/RPI-RP2/" >&2
					echo "[build.sh] Device will reboot automatically after copy completes." >&2
				else
					echo "[build.sh] ❌ No RPI-RP2 drive found and picotool not available." >&2
					echo "[build.sh] Please put your device in BOOTSEL mode and manually copy:" >&2
					echo "[build.sh]   $UF2_FILE" >&2
					echo "[build.sh] to the mounted RPI-RP2 drive." >&2
					exit 1
				fi
			fi
		else
			echo "[build.sh] ERROR: UF2 file not found at $UF2_FILE" >&2
			exit 1
		fi
	else
		echo "[build.sh] ERROR: Build failed!" >&2
		exit 1
	fi
fi

