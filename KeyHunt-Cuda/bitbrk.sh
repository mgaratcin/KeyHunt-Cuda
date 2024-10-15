#!/bin/bash

# Define start and end of the total range in hexadecimal
START_HEX="693c041e000000000"
END_HEX="7ffffffffffffffff"
CHUNK_SIZE=1099511627776 # 2^40 in decimal

# Define target address
target_address="1BY8GQbnueYofwSuFAT3USAhGjPrkxDdW9"

# Function to convert hex to decimal using bc
hex_to_dec() {
  # Convert hex input to uppercase to ensure bc compatibility
  hex_upper=$(echo "$1" | tr '[:lower:]' '[:upper:]')
  echo "ibase=16; ${hex_upper}" | bc
}

# Function to convert decimal to hex using bc
dec_to_hex() {
  echo "obase=16; ${1}" | bc
}

# Convert START and END to decimal for easier iteration
start_dec=$(hex_to_dec "$START_HEX")
end_dec=$(hex_to_dec "$END_HEX")

# Debug: Print start and end decimal values to verify correctness
echo "Start Decimal: $start_dec"
echo "End Decimal: $end_dec"

# Check if conversion was successful
if [ -z "$start_dec" ] || [ -z "$end_dec" ]; then
  echo "Error: Failed to convert hex values to decimal. Please check the input values."
  exit 1
fi

# Check if start is less than end
if [ $(echo "$start_dec >= $end_dec" | bc) -eq 1 ]; then
  echo "Error: Start value is not less than end value. Please check the input range."
  exit 1
fi

# Iterate over the keyspace in 35-bit chunks
current_start=$start_dec
while [ $(echo "$current_start < $end_dec" | bc) -eq 1 ]; do
  # Calculate the end of the current chunk
  current_end=$(echo "$current_start + $CHUNK_SIZE - 1" | bc)
  if [ $(echo "$current_end > $end_dec" | bc) -eq 1 ]; then
    current_end=$end_dec
  fi

  # Convert current range to hexadecimal
  range_start_hex=$(dec_to_hex "$current_start")
  range_end_hex=$(dec_to_hex "$current_end")

  # Check for conversion errors
  if [ -z "$range_start_hex" ] || [ -z "$range_end_hex" ]; then
    echo "Error: Failed to convert decimal to hex. Please check the input values."
    exit 1
  fi

  echo "Processing range: $range_start_hex to $range_end_hex"

  # Run the KeyHunt command with a 20-second timeout
  timeout 100 ./KeyHunt -t 0 -g --gpui 0,1,2,3,4,5,6,7 --gpux 256,256,256,256,256,256,256,256,256,256,256,256,256,256,256,256 -m address --coin BTC --range ${range_start_hex}:${range_end_hex} ${target_address} > output.txt 2>&1

  # Ensure the command executed successfully or was timed out
  if [ $? -eq 124 ]; then
    echo "Info: KeyHunt command timed out after 20 seconds. Moving to the next range."
  elif [ $? -ne 0 ]; then
    echo "Error: KeyHunt command failed."
    exit 1
  fi

  # Debug: Display output for each iteration
  echo "--- KeyHunt Output Start ---"
  cat output.txt
  echo "--- KeyHunt Output End ---"

  # Check if an incorrect key or warning is found by examining the output
  if grep -q -E "Warning, wrong private key generated|WIF" output.txt; then
    echo "Warning: Wrong private key or WIF generated. Stopping."
    exit 1
  fi

  # Check for a clear indicator that the correct key was found
  if grep -q "Target address found" output.txt; then
    echo "Target address found. Stopping."
    exit 0
  fi

  # Move to the next chunk
  current_start=$(echo "$current_end + 1" | bc)
done

echo "Completed all ranges without finding the target address."
