# Arma 3 Auto Updater Script

## Overview
This script is designed to automate the update process for an Arma 3 server. Main purpose of this script is to update server mods with account with Steam Guard enabled. Since normal entrypoint.sh script can't handle Steam Guard, this script is used to update mods from host machine.

## Author
Part of this script is based on the entrypoint.sh script from the [Arma3 Egg](https://github.com/parkervcp/eggs/tree/master/game_eggs/steamcmd_servers/arma/arma3) by David Wolfe (Red-Thirten).
Script was modified by Kaktus1549.

## Usage
1. **Download the Script**: Download the `auto_updater.sh` script to your server.
    ```sh
    git clone https://github.com/Kaktus1549/PterodactylStuff.git
    cd PterodactylStuff/Arma3
    ```
2. **Make Executable**: Make sure the script has executable permissions. You can set this by running:
    ```sh
    chmod +x ./auto_updater.sh
    ```
3. **Run the Script**: Execute the script manually or set up a cron job to run it at regular intervals:
    ```sh
    ./auto_updater.sh <arma3_volume_path> <steamusername> <modlist_filename>
    ```

## Notes
- Ensure that you have the necessary permissions to run the script and update the server files.
- Script must be run as root or with sudo permissions.
- Make sure that modlist file is in the arma3_volume_path directory.

## Example usage:

```sh
sudo ./auto_updater.sh /var/lib/pterodactyl/volumes/fda841aa-e9fb-4b91-aff0-cca8b1d034e0 humlik9 lmaomatkatvoje.html
```