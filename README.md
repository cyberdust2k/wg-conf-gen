# wg-conf-gen
Fully automatic, basic bash script for generating functional Wireguard-configs, with optional QR code support

# usage
At the top of the script are editable variables you can customize based on your local setup.

You can also specify with the "-l" flag whether the new peer should have full internet access or only local access or use the flag "-n <name>" to generate a custom wireguard config.

Enabling IPv6 is handled by the variable "$ena_v6". By default it contains "1", but the script only checks if the variable is non-zero so it can be anything.
