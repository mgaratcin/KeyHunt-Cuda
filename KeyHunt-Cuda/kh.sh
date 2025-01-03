#!/bin/bash

# =============================================================================
# Script Name: run_keyhunt.sh
# Description: Automates the execution of the KeyHunt program with randomized
#              non-overlapping ranges, logs progress, and handles graceful
#              termination.
# =============================================================================

# ----------------------------- Configuration ------------------------------

# Path to the KeyHunt executable
KEYHUNT_PATH="./KeyHunt"  # Ensure this is the correct executable name

# Output file to log completed ranges
OUTPUT_FILE="checked.txt"

# Fixed prefixes and suffixes for the range
FIXED_START_PREFIX="47cd"
FIXED_START_SUFFIX="0000000000"
FIXED_END_PREFIX="47cd"
FIXED_END_SUFFIX="ffffffffff"  # Ensure this is exactly 10 'f's

# Other KeyHunt parameters
COIN="BTC"
ADDRESS_MODE="address"
WALLET_ADDRESS="1BY8GQbnueYofwSuFAT3USAhGjPrkxDdW9"
GPUI="0,1,2,3,4,5,6,7"  # Updated to match your manual command
GPUX="4092,256,4092,256,4092,256,4092,256,4092,256,4092,256,4092,256,4092,256"  # Updated to match your manual command
THREADS=0  # Specify number of CPU threads as per your manual command

# Number of variable hexadecimal characters in the range
TARGET_RANGE_LENGTH=3

# Temporary file to store shuffled combinations
SHUFFLED_COMBOS_FILE="shuffled_combos.tmp"

# =============================================================================

# Flag to indicate termination
terminate=false

# --------------------------- Signal Handling ------------------------------

# Function to handle Ctrl+C
handle_interrupt() {
    echo ""
    echo "[INFO] Interrupt received. Shutting down gracefully..."
    terminate=true
}

# Trap SIGINT (Ctrl+C)
trap handle_interrupt SIGINT

# ------------------------- Helper Functions ------------------------------

# Function to generate all 5-character hexadecimal combinations
generate_combinations() {
    echo "[INFO] Generating all possible 5-character hexadecimal combinations..."
    # Using printf to format numbers from 0 to 1048575 (0xFFFFF) as 5-digit hex
    for i in $(seq 0 4095); do
        printf "%03x\n" "$i"
    done
}

# Function to load already checked combinations into an associative array
declare -A checked_ranges_map

load_checked_ranges() {
    if [[ -f "$OUTPUT_FILE" ]]; then
        echo "[INFO] Loading already checked ranges from $OUTPUT_FILE..."
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Extract the combination from the range string
            # Example range: 55bc43d0000000000:55bc43dffffffffff
            # Combination is the 5 characters after the prefix "55"
            combo=$(echo "$line" | cut -c3-7)
            checked_ranges_map["$combo"]=1
        done < "$OUTPUT_FILE"
        echo "[INFO] Loaded ${#checked_ranges_map[@]} already checked ranges."
    else
        echo "[INFO] No existing $OUTPUT_FILE found. Starting fresh."
    fi
}

# Function to shuffle combinations and save to a temporary file
shuffle_combinations() {
    echo "[INFO] Shuffling the combinations to ensure random search order..."
    generate_combinations | shuf > "$SHUFFLED_COMBOS_FILE"
    echo "[INFO] Shuffled combinations saved to $SHUFFLED_COMBOS_FILE."
}

# Function to clean up temporary files upon exit
cleanup() {
    if [[ -f "$SHUFFLED_COMBOS_FILE" ]]; then
        rm -f "$SHUFFLED_COMBOS_FILE"
    fi
}

# Ensure cleanup is done on script exit
trap cleanup EXIT

# Function to run KeyHunt with the specified range
run_keyhunt() {
    local range_str="$1"

    # Construct the KeyHunt command
    # Adding debug statement to print the command being executed
    echo "[DEBUG] Executing: $KEYHUNT_PATH -t $THREADS -g --gpui $GPUI --gpux $GPUX -m $ADDRESS_MODE --coin $COIN --range $range_str $WALLET_ADDRESS"

    # Run KeyHunt and capture both stdout and stderr
    "$KEYHUNT_PATH" -t "$THREADS" -g --gpui "$GPUI" --gpux "$GPUX" \
        -m "$ADDRESS_MODE" --coin "$COIN" --range "$range_str" "$WALLET_ADDRESS"
}

# =============================================================================

# ----------------------------- Main Script ----------------------------------

echo "[INFO] Starting KeyHunt automation script..."

# Check if KeyHunt executable exists and is executable
if [[ ! -x "$KEYHUNT_PATH" ]]; then
    echo "[ERROR] KeyHunt executable not found or not executable at $KEYHUNT_PATH."
    exit 1
fi

# Load already checked ranges
load_checked_ranges

# Shuffle combinations
shuffle_combinations

# Total number of combinations
TOTAL_COMBINATIONS=$(wc -l < "$SHUFFLED_COMBOS_FILE")
echo "[INFO] Total combinations to process: $TOTAL_COMBINATIONS"

# Initialize counter
COUNTER=0

# Read shuffled combinations line by line
while IFS= read -r combo || [[ -n "$combo" ]]; do
    # Increment counter
    COUNTER=$((COUNTER + 1))

    # Check if termination was requested
    if [[ "$terminate" = true ]]; then
        echo "[INFO] Script terminated by user at combination $COUNTER."
        break
    fi

    # Skip already checked combinations
    if [[ -n "${checked_ranges_map[$combo]}" ]]; then
        continue
    fi

    # Ensure the combo is exactly 5 characters
    if [[ ${#combo} -ne $TARGET_RANGE_LENGTH ]]; then
        echo "[WARNING] Invalid combo length for '$combo'. Skipping."
        continue
    fi

    # Construct the range string
    start_range="${FIXED_START_PREFIX}${combo}${FIXED_START_SUFFIX}"
    end_range="${FIXED_END_PREFIX}${combo}${FIXED_END_SUFFIX}"
    range_str="${start_range}:${end_range}"

    # Debug: Print the constructed range
    echo "[DEBUG] Range constructed: $range_str"

    echo "[${COUNTER}/${TOTAL_COMBINATIONS}] Running KeyHunt for range: $range_str"

    # Run KeyHunt and capture output
    output=$(run_keyhunt "$range_str" 2>&1)

    # Debug: Print KeyHunt output
    echo -e "[DEBUG] KeyHunt Output:\n$output"

    # Check for success in the output
    if echo "$output" | grep -q "PubAddress:" && echo "$output" | grep -q "Priv (WIF):"; then
        echo ""
        echo "================================================================================="
        echo "SUCCESS: Successful hit found!"
        echo "$output"
        echo "================================================================================="
        echo "$range_str" >> "$OUTPUT_FILE"
        exit 0
    fi

    # Log the completed range
    echo "$range_str" >> "$OUTPUT_FILE"
    checked_ranges_map["$combo"]=1

done < "$SHUFFLED_COMBOS_FILE"

# Check if all combinations were processed
if [[ "$COUNTER" -ge "$TOTAL_COMBINATIONS" && "$terminate" != true ]]; then
    echo "[INFO] All combinations have been processed."
fi

echo "[INFO] Exiting script."

# =============================================================================
