#!/bin/bash

# ============================================================================
# CONFIGURATION - Set up the basic settings for the script
# ============================================================================

# The system ID we're starting from (passed as first argument)
START_SYSTEM_ID=$1

# Maximum number of jumps to search (default is 10 if not specified)
MAX_JUMPS=${2:-10}

# The base URL for EVE Online's ESI API
ESI_BASE="https://esi.evetech.net/latest"

# Specify planet type to look for 
# Storm = 2017
PLANET_TYPE=2017

# We only care about planets with MORE than this many storms
STORM_THRESHOLD=2

# ============================================================================
# INPUT VALIDATION - Check if the user gave us what we need
# ============================================================================

# If the user didn't provide a system ID, show them how to use the script
if [ -z "$START_SYSTEM_ID" ]; then
    echo "Usage: $0 <system_id> [max_jumps]"
    exit 1
fi

# ============================================================================
# GET STARTING SYSTEM NAME - Look up the name of our starting system
# ============================================================================

# Query the ESI API to get info about our starting system
start_system_name=$(curl -s "$ESI_BASE/universe/systems/$START_SYSTEM_ID/" | jq -r '.name')

# Create the output filename using the jump distance and system name
output_file="storm_within_${MAX_JUMPS}_${start_system_name}.csv"

# Tell the user what we're doing
echo "Starting from: $start_system_name (ID: $START_SYSTEM_ID)"
echo "Output file: $output_file"

# ============================================================================
# INITIALIZE DATA STRUCTURES - Set up containers to store our data
# ============================================================================

# This is like a notebook where we write down which systems we've already visited
# (so we don't check the same system twice)
declare -A visited

# This is our "to-do list" of systems we still need to check
declare -a queue

# This will store all the systems that have more than 4 storm planets
declare -a results

# ============================================================================
# START THE SEARCH - Add the starting system to our to-do list
# ============================================================================

# Put the starting system in the queue with 0 jumps (we're already there)
queue=("$START_SYSTEM_ID:0")

# Mark the starting system as visited so we don't check it again
visited[$START_SYSTEM_ID]=1

# ============================================================================
# MAIN LOOP - Process each system in our to-do list (BFS algorithm)
# ============================================================================

# Keep going while there are still systems in our to-do list
while [ ${#queue[@]} -gt 0 ]; do
    
    # Take the first system from our to-do list
    current="${queue}"
    
    # Remove it from the to-do list (shift everything else forward)
    queue=("${queue[@]:1}")
    
    # Split the system info into system ID and number of jumps
    # (they were stored together as "30000142:0")
    IFS=':' read -r sys_id jumps <<< "$current"
    
    # Tell the user we're checking this system
    echo "Processing system $sys_id (jumps: $jumps)" >&2
    
   # ========================================================================
# QUERY THE SYSTEM - Get all the planet information
# ========================================================================

# Ask the ESI API for information about this system
system_data=$(curl -s "$ESI_BASE/universe/systems/$sys_id/")

# Extract just the system's name from the response
system_name=$(echo "$system_data" | jq -r '.name')

# Extract all planet IDs from the system
planet_ids=$(echo "$system_data" | jq -r '.planets[].planet_id')

# Count how many planets are "Storm" type planets
storm_count=0
for planet_id in $planet_ids; do
    # Query each planet individually to get its type
    planet_data=$(curl -s "$ESI_BASE/universe/planets/$planet_id/")
    planet_type_id=$(echo "$planet_data" | jq -r '.type_id')
    
    # If this planet is a Storm type (type_id 20001), increment the counter
    if [ "$planet_type_id" == "$PLANET_TYPE" ]; then
        ((storm_count++))
    fi
done

# ========================================================================
# CHECK IF THIS SYSTEM IS INTERESTING - Does it have enough storms?
# ========================================================================

# If this system has more storm planets than our threshold (4), save it
if [ "$storm_count" -gt "$STORM_THRESHOLD" ]; then
    # Add this system to our results list
    results+=("$sys_id,$system_name,$jumps,$storm_count")
    # Tell the user we found something good
    echo "  Found $storm_count storm planets!" >&2
fi

    # ========================================================================
    # EXPLORE NEIGHBORS - Find connected systems and add them to our to-do list
    # ========================================================================
    
    # Only explore further if we haven't reached our jump limit
    if [ "$jumps" -lt "$MAX_JUMPS" ]; then
        
        # Get all the stargate IDs from this system
        stargate_ids=$(echo "$system_data" | jq -r '.stargates[]? // empty')
        
        # Loop through each stargate ID
        while read -r stargate_id; do
            
            # Make sure we got a valid stargate ID
            if [ -n "$stargate_id" ]; then
                
                # Query the ESI API to get information about this specific stargate
                # This tells us which system it connects to
                stargate_data=$(curl -s "$ESI_BASE/universe/stargates/$stargate_id/")
                
                # Extract the destination system ID from the stargate data
                dest_sys=$(echo "$stargate_data" | jq -r '.destination.system_id // empty')
                
                # Check if we got a valid system ID and haven't visited it yet
                if [ -n "$dest_sys" ] && [ -z "${visited[$dest_sys]}" ]; then
                    
                    # Mark this system as visited
                    visited[$dest_sys]=1
                    
                    # Add this system to our to-do list with incremented jump count
                    queue+=("$dest_sys:$((jumps + 1))")
                fi
            fi
        done <<< "$stargate_ids"
    fi
done


# ============================================================================

# SORT RESULTS - Arrange systems by distance (jumps) in descending order

# ============================================================================



# Sort the results array by the third column (jumps) in reverse/descending order

# This puts systems that are furthest away first

IFS=$'\n' sorted_results=($(sort -t',' -k3 -rn <(printf '%s\n' "${results[@]}")))



# ============================================================================

# WRITE CSV FILE - Save the results to a file

# ============================================================================



# Create the CSV file with headers and data

{

    # Write the header row with column names

    echo "systemid,system_name,jumps_from_${start_system_name},storm_planet_count"

    

    # Write all the results (now sorted by jumps descending)

    printf '%s\n' "${sorted_results[@]}"

} > "$output_file"



# ============================================================================

# SUMMARY - Tell the user what we found

# ============================================================================



echo "Done! Results saved to $output_file"

echo "Found ${#results[@]} systems with more than $STORM_THRESHOLD storm planets"
