#!/bin/bash

# Define start and end of the range in hexadecimal
START_HEX="7218E420000000000"
END_HEX="7218E42FFFFFFFFFF"
CHUNK_SIZE="34359738368"  # 2^35, which equals 34359738368 in decimal

# Function to convert decimal to hexadecimal
dec2hex() {
    echo "obase=16; $1" | bc
}

# Function to convert hexadecimal to decimal using bc for arbitrary-precision support
hex2dec() {
    echo "ibase=16; $1" | bc
}

# Convert start and end from hex to decimal for easier range operations
START_DEC=$(hex2dec "$START_HEX")
END_DEC=$(hex2dec "$END_HEX")

# Iterate over the range in exactly 35-bit chunks using bc
CURRENT_DEC=$START_DEC
while [ "$(echo "$CURRENT_DEC < $END_DEC" | bc)" -eq 1 ]; do
    NEXT_DEC=$(echo "$CURRENT_DEC + $CHUNK_SIZE" | bc)
    
    if [ "$(echo "$NEXT_DEC > $END_DEC" | bc)" -eq 1 ]; then
        NEXT_DEC=$END_DEC
    fi
    
    # Convert decimal back to hex for range values
    CURRENT_HEX=$(dec2hex "$CURRENT_DEC")
    NEXT_HEX=$(dec2hex "$NEXT_DEC")

    echo "Processing range $CURRENT_HEX:$NEXT_HEX"

    # Run KeyHunt for the current 35-bit chunk and check for the solution in real time
    ./KeyHunt -t 0 -g --gpui 0 --gpux 4092,256 -m address --coin BTC --range "$CURRENT_HEX:$NEXT_HEX" "1BY8GQbnueYofwSuFAT3USAhGjPrkxDdW9" | while IFS= read -r line
    do
        echo "$line"  # Show the line for logging purposes
        if echo "$line" | grep -q "PivK :"; then
            echo "Solution found!"
            echo "$line"
            kill $$  # Stop the entire script
        fi
    done

    # Update CURRENT_DEC to the next range
    CURRENT_DEC=$NEXT_DEC
done

echo "All ranges processed. No solution found."
