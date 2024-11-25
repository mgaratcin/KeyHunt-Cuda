#!/bin/bash

# Check for number of GPUs argument
if [ -z "$1" ]; then
  echo "Usage: $0 <number_of_gpus>"
  exit 1
fi

NUM_GPUS=$1

# Define start and end of the total range in hexadecimal
START_HEX="41000000000000000"
END_HEX="6ffffffffffffffff"
CHUNK_SIZE=$(echo "2^34" | bc) # 17179869184

# Timeout duration in seconds
TIMEOUT_DURATION=20

# Define target address
target_address="1BY8GQbnueYofwSuFAT3USAhGjPrkxDdW9"

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

current_start="$start_dec"

while [ "$(echo "$current_start <= $end_dec" | bc)" -eq 1 ]; do
  # Start processes for NUM_GPUS or remaining chunks
  for (( i=0; i<NUM_GPUS; i++ ))
  do
    if [ "$(echo "$current_start > $end_dec" | bc)" -eq 1 ]; then
      break
    fi

    # Calculate range start and end using bc
    range_start_dec="$current_start"
    range_end_dec=$(echo "$range_start_dec + $CHUNK_SIZE - 1" | bc)
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

    # Run the KeyHunt command with a timeout
    timeout $TIMEOUT_DURATION ./KeyHunt -t 0 -g --gpui $i --gpux 128,128 \
    -m address --coin BTC --range ${range_start_hex}:${range_end_hex} \
    ${target_address} > output_${i}.txt 2>&1 &

    # Update current_start for next chunk using bc
    current_start=$(echo "$range_end_dec + 1" | bc)
  done

  # Wait for all processes to finish
  wait

  # Check outputs for success or warnings
  for (( i=0; i<NUM_GPUS; i++ ))
  do
    if [ -f output_${i}.txt ]; then
      # Check for incorrect key or warnings
      if grep -q -E "Warning, wrong private key generated|WIF" output_${i}.txt; then
        echo "GPU $i Warning: Wrong private key or WIF generated."
        # Kill all KeyHunt processes and exit
        pkill -f KeyHunt
        exit 1
      fi

      # Check if the target address was found
      if grep -q "Target address found" output_${i}.txt; then
        echo "GPU $i: Target address found."
        # Kill all KeyHunt processes and exit
        pkill -f KeyHunt
        exit 0
      fi
    fi
  done

done

echo "Completed all ranges without finding the target address."
