#!/bin/bash

# Start and end of the keyspace for 66 bits (as hexadecimal strings)
start_range="6901ec527c1e0f8ea"
end_range="69f1ec527c1e0f8ea"

# Convert start and end range to decimal using Python
current_start=$(python3 -c "print(int('$start_range', 16))")
end_range_dec=$(python3 -c "print(int('$end_range', 16))")

# Print the results of the Python conversion for debugging
echo "Current Start (Decimal): $current_start"
echo "End Range (Decimal): $end_range_dec"

# Set the chunk size to 32 bits
chunk_size=$((1 << 32))

# Print the chunk size for verification
echo "Chunk Size (Decimal): $chunk_size"

# Ensure output.txt exists and clear old content
> output.txt

# Flag to indicate if warning was detected
warning_detected=0

# Function to run KeyHunt on a specific range (PARALLEL)
run_keyhunt () {
    local start=$1
    local end=$2
    echo "Running KeyHunt on range: $start to $end"

    # Run KeyHunt with stdbuf to flush output immediately and log to output.txt
    stdbuf -oL ./KeyHunt -t 0 -g --gpui 0 --gpux 256,256 -m address --coin BTC --range "$start:$end" 1BY8GQbnueYofwSuFAT3USAhGjPrkxDdW9 >> output.txt 2>&1 &
}

# Function to monitor output.txt for the warning message
monitor_output() {
    echo "Monitoring output.txt for warning..."

    tail -n 0 -f output.txt | while read -r line; do
        echo "Read: $line"  # Log every line read
        if echo "$line" | grep -q "Warning"; then
            echo "Warning found! Terminating all KeyHunt processes."
            pkill KeyHunt  # Terminate all KeyHunt processes
            warning_detected=1  # Set the warning flag
            break  # Stop monitoring
        fi
    done
}

# Clean up all processes when script is terminated
trap 'echo "Terminating all processes."; pkill KeyHunt; exit' SIGINT SIGTERM

# Function to process the keyspace in batches of four in PARALLEL
process_keyspace () {
    echo "Starting keyspace processing..."

    # Start the monitor in the background
    monitor_output &

    while [ "$(python3 -c "print($current_start < $end_range_dec)")" == "True" ]; do
        # Print the current start and end for debugging
        echo "Processing from Decimal: $current_start to $end_range_dec"

        # Create an array to store background process IDs
        local pids=()

        for i in {1..4}; do
            if [ "$(python3 -c "print($current_start < $end_range_dec)")" == "True" ] && [ "$warning_detected" -eq 0 ]; then
                # Calculate the current end of the chunk
                current_end=$(python3 -c "print($current_start + $chunk_size - 1)")
                if [ "$(python3 -c "print($current_end > $end_range_dec)")" == "True" ]; then
                    current_end=$end_range_dec
                fi

                # Ensure current_end is valid
                if [[ -z "$current_end" ]]; then
                    echo "Error: Invalid current_end value."
                    exit 1
                fi

                # Print the current chunk range being processed
                echo "Current Chunk Start (Decimal): $current_start"
                echo "Current Chunk End (Decimal): $current_end"

                # Convert current_start and current_end back to hex
                start_hex=$(python3 -c "print(hex($current_start)[2:])")
                end_hex=$(python3 -c "print(hex($current_end)[2:])")

                # Ensure conversion succeeded
                if [[ -z "$start_hex" || -z "$end_hex" ]]; then
                    echo "Error: Could not convert range from decimal to hex."
                    exit 1
                fi

                echo "Processing range: $start_hex to $end_hex"

                # Run KeyHunt in the background (parallel execution)
                run_keyhunt $start_hex $end_hex

                # Store the process ID of the background task
                pids+=($!)

                # Increment the start for the next range
                current_start=$(python3 -c "print($current_end + 1)")
            fi
        done

        # Wait for all parallel processes to finish before continuing to the next batch
        for pid in "${pids[@]}"; do
            wait $pid
        done

        # If warning is detected, stop further execution
        if [ "$warning_detected" -eq 1 ]; then
            echo "Warning detected, stopping further execution."
            break
        fi
    done
}

# Run the keyspace processing function
process_keyspace
