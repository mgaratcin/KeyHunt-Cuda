#!/bin/bash

# Check for number of GPUs argument
if [ -z "$1" ]; then
  echo "Usage: $0 <number_of_gpus>"
  exit 1
fi

NUM_GPUS=$1

# Define start and end of the total range in hexadecimal
START_HEX="6A147AE147AE147AE"
END_HEX="6AB851EB851EB851E"
CHUNK_SIZE=$(echo "2^34" | bc) # 17179869184

# Timeout duration in seconds
TIMEOUT_DURATION=20

# Define target address
target_address="1BY8GQbnueYofwSuFAT3USAhGjPrkxDdW9"

# Initialize or create the complete.txt file
if [ ! -f complete.txt ]; then
  touch complete.txt
fi

# Function to convert hex to decimal using bc
hex_to_dec() {
  echo "ibase=16; $(echo "$1" | tr '[:lower:]' '[:upper:]')" | bc
}

# Function to convert decimal to hex using bc
dec_to_hex() {
  echo "obase=16; ${1}" | bc | tr '[:upper:]' '[:lower:]'
}

# Convert START and END to decimal
start_dec=$(hex_to_dec "$START_HEX")
end_dec=$(hex_to_dec "$END_HEX")

# Compute total range
total_range=$(echo "$end_dec - $start_dec + 1" | bc)

# Compute maximum random offset
max_random=$(echo "$total_range - $CHUNK_SIZE" | bc)

if [ "$(echo "$max_random <= 0" | bc)" -eq 1 ]; then
  echo "Error: CHUNK_SIZE is larger than the total range."
  exit 1
fi

# Centralized range allocation function
get_unique_range() {
  while true; do
    # Generate random offset using Python's secrets module
    range_offset=$(python3 -c "import secrets; print(secrets.randbelow(int($max_random)))")

    # Calculate range start and end
    range_start_dec=$(echo "$start_dec + $range_offset" | bc)
    range_end_dec=$(echo "$range_start_dec + $CHUNK_SIZE - 1" | bc)

    # Ensure range_end_dec does not exceed end_dec
    if [ "$(echo "$range_end_dec > $end_dec" | bc)" -eq 1 ]; then
      range_end_dec="$end_dec"
    fi

    # Convert to hex
    range_start_hex=$(dec_to_hex "$range_start_dec")
    range_end_hex=$(dec_to_hex "$range_end_dec")
    range_identifier="${range_start_hex}:${range_end_hex}"

    # Lock the complete.txt file
    exec 200>complete.txt.lock
    flock -x 200

    # Check if range is already in complete.txt
    if ! grep -Fxq "$range_identifier" complete.txt; then
      # Append the processed range to complete.txt
      echo "$range_identifier" >> complete.txt
      # Release the lock
      flock -u 200
      exec 200>&-
      echo "$range_identifier"
      return
    fi

    # Release the lock if duplicate
    flock -u 200
    exec 200>&-
  done
}

# Main loop for GPU processing
while true; do
  for (( i=0; i<NUM_GPUS; i++ )); do
    # Get a unique range
    range=$(get_unique_range)
    range_start_hex=${range%%:*}
    range_end_hex=${range##*:}

    echo "GPU $i Processing range: $range_start_hex to $range_end_hex"

    # Run the KeyHunt command with a timeout
    timeout $TIMEOUT_DURATION ./KeyHunt -t 0 -g --gpui $i --gpux 128,128 \
    -m address --coin BTC --range "$range_start_hex:$range_end_hex" \
    "$target_address" > "output_${i}.txt" 2>&1 &
  done

  # Wait for all processes to finish
  wait

  # Check outputs for success or warnings
  for (( i=0; i<NUM_GPUS; i++ )); do
    if [ -f "output_${i}.txt" ]; then
      if grep -q "Target address found" "output_${i}.txt"; then
        echo "GPU $i: Target address found!"
        pkill -f KeyHunt
        exit 0
      fi
    fi
  done
done
