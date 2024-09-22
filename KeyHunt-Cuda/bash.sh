#!/bin/bash

# Start and end of the keyspace for 66 bits (as hexadecimal strings)
start_range="40000000000000000"
end_range="7ffffffffffffffff"

# Convert start and end range to decimal using Python
current_start=$(python3 -c "print(int('$start_range', 16))")
end_range_dec=$(python3 -c "print(int('$end_range', 16))")

# Set the chunk size to 35 bits
chunk_size=$((1 << 44))

# Ensure output.txt exists and clear old content
> output.txt

# Flag to indicate if warning was detected
warning_detected=0

# Function to run KeyHunt on a specific range (PARALLEL)
run_keyhunt () {
    local start=$1
    local end=$2
    echo "Running KeyHunt on range: $start to $end"
    stdbuf -oL ./KeyHunt -t 0 -g --gpui 0,1,2,3,4,5,6,7 --gpux 4092,256,4092,256,4092,256,4092,256,4092,256,4092,256,4092,256,4092,256 -m address --coin BTC --range "$start:$end" 1BY8GQbnueYofwSuFAT3USAhGjPrkxDdW9 >> output.txt 2>&1 &
}

# Function to monitor output.txt for the warning message
monitor_output() {
    echo "Monitoring output.txt for warning..."
    tail -n 0 -f output.txt | while read -r line; do
        if echo "$line" | grep -q "Warning"; then
            echo "Warning found! Terminating all KeyHunt processes."
            pkill KeyHunt  # Terminate all KeyHunt processes
            warning_detected=1  # Set the warning flag
            break
        fi
    done
}

# Clean up all processes when script is terminated
trap 'echo "Terminating all processes."; pkill KeyHunt; exit' SIGINT SIGTERM

# Function to process the keyspace in batches of four in PARALLEL, with a 69-second timer
process_keyspace () {
    echo "Starting keyspace processing..."

    # Start the monitor in the background
    monitor_output &

    while [ "$(python3 -c "print($current_start < $end_range_dec)")" == "True" ]; do
        echo "Processing from Decimal: $current_start to $end_range_dec"

        # Create an array to store background process IDs
        local pids=()
        local start_time=$(date +%s)  # Record the start time

        for i in {1..1}; do
            if [ "$(python3 -c "print($current_start < $end_range_dec)")" == "True" ] && [ "$warning_detected" -eq 0 ]; then
                current_end=$(python3 -c "print($current_start + $chunk_size - 1)")
                if [ "$(python3 -c "print($current_end > $end_range_dec)")" == "True" ]; then
                    current_end=$end_range_dec
                fi

                start_hex=$(python3 -c "print(hex($current_start)[2:])")
                end_hex=$(python3 -c "print(hex($current_end)[2:])")

                echo "Processing range: $start_hex to $end_hex"
                run_keyhunt $start_hex $end_hex

                # Store the process ID of the background task
                pids+=($!)
                
                current_start=$(python3 -c "print($current_end + 1)")
            fi
        done

        # Sleep for 240 seconds and then kill all KeyHunt processes
        while true; do
            current_time=$(date +%s)
            elapsed=$((current_time - start_time))

            if [ $elapsed -ge 240 ]; then
                echo "240 seconds have passed, moving to the next range."
                pkill KeyHunt  # Terminate all KeyHunt processes
                break
            fi

            # Check every second to avoid tight loops
            sleep 1
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
