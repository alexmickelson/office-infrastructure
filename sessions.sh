#!/bin/bash

# Define the servers array
servers=(
  "office-server1"
  "office-server2"
  "office-server3"
  "office-server4"
  "office-server5"
)

# Iterate over the servers array
for server in "${servers[@]}"; do
    echo "--------------------------------------"
    echo "Current user sessions on ${server}:"
    echo "--------------------------------------"

    # SSH into the server and run the command to list current user sessions
    ssh "${server}" "who"

    echo # Adding an extra line for spacing
done
