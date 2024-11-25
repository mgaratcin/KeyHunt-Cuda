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

# Initialize or clear the complete.txt file
: > complete.txt

# Function to convert hex to decimal using bc
hex_to_dec() {
  echo "ibase=16; $(echo "$1" | tr '[:lower:]' '[:upper:]')" | bc
}

# Function to convert decimal to hex using bc
dec_to_hex() {
  echo "obase=16; ${1}" | bc
}

# Convert START and END to decimal
start_dec=$(hex_to_dec "$START_HEX")
end_dec=$(hex_to_dec "$END_HEX")

# Debug: Print start and end decimal values
echo "Start Decimal: $start_dec"
echo "End Decimal: $end_dec"

# Check if conversion was successful
if [ -z "$start_dec" ] || [ -z "$end_dec" ]; then
  echo "Error: Failed to convert hex values to decimal. Please check the input values."
  exit 1
fi

# Check if start is less than end using bc
if [ "$(echo "$start_dec >= $end_dec" | bc)" -eq 1 ]; then
  echo "Error: Start value is not less than end value. Please check the input range."
  exit 1
fi

# Compute total range
total_range=$(echo "$end_dec - $start_dec + 1" | bc)

# Compute maximum random offset
max_random=$(echo "$total_range - $CHUNK_SIZE" | bc)

if [ "$(echo "$max_random <= 0" | bc)" -eq 1 ]; then
  echo "Error: CHUNK_SIZE is larger than the total range."
  exit 1
fi

while true; do
  # Start processes for NUM_GPUS
  for (( i=0; i<NUM_GPUS; i++ ))
  do
    # Generate random offset using Python's secrets module
    range_offset=$(python3 -c "import secrets; print(secrets.randbelow($max_random))")

    # Calculate range start and end using bc
    range_start_dec=$(echo "$start_dec + $range_offset" | bc)
    range_end_dec=$(echo "$range_start_dec + $CHUNK_SIZE - 1" | bc)

    # Ensure range_end_dec does not exceed end_dec
    if [ "$(echo "$range_end_dec > $end_dec" | bc)" -eq 1 ]; then
      range_end_dec="$end_dec"
    fi

    # Convert to hex
    range_start_hex=$(dec_to_hex "$range_start_dec")
    range_end_hex=$(dec_to_hex "$range_end_dec")

    # Check for conversion errors
    if [ -z "$range_start_hex" ] || [ -z "$range_end_hex" ]; then
      echo "Error: Failed to convert decimal to hex. Please check the input values."
      exit 1
    fi

    echo "GPU $i Processing range: $range_start_hex to $range_end_hex"

    # Append the processed range to complete.txt in the desired format
    echo "${range_start_hex}:${range_end_hex}" >> complete.txt

    # Run the KeyHunt command with a timeout
    timeout $TIMEOUT_DURATION ./KeyHunt -t 0 -g --gpui $i --gpux 128,128 \
    -m address --coin BTC --range ${range_start_hex}:${range_end_hex} \
    ${target_address} > output_${i}.txt 2>&1 &
  done

  # Wait for all processes to finish
  wait

  # Check outputs for success or warnings
  for (( i=0; i<NUM_GPUS; i++ ))
  do
    if [ -f output_${i}.txt ]; then
      # Check for incorrect key or warnings
      if grep -q -E "Warning, wrong private key generated|WIF" output_${i}.txt; then
        echo "GPU $i Range Hit!"
        # Kill all KeyHunt processes and exit
        pkill -f KeyHunt
        exit 1
      fi

      # Check if the target address was found
      if grep -q "Target address found" output_${i}.txt; then
        echo "GPU $i: Range Hit!"
        # Kill all KeyHunt processes and exit
        pkill -f KeyHunt
        exit 0
      fi
    fi
  done

done

echo "Completed all ranges without finding the target address."
