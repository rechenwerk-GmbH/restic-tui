#!/bin/bash

# Author: pk7
# Description: A simple-to-use script to install and use restic with a menu based TUI or with arguments
# Note: Please edit the .env file before running the script
# Dependencies: curl, bzip2
# Usage: sudo ./restic.sh [OPTION] [ARGUMENT]
# Options: 
#  No option - Display menu
#   1 - Install restic
#   2 - Uninstall restic
#   3 - Initialize Repository
#   4 - Check Repository Integrity
#   5 - Prune Repository (Remove unused data)
#   6 - Unlock Repository
#   7 - Backup whole system
#   8 - Backup specific directory or file
#   9 - Forget snapshots older then KEEP_DAYS in .env file
#   10 - Mount Repository
#   11 - List Snapshots
#   12 - Schedule Backup weekly/daily
#   13 - Schedule Forget weekly/daily

##### Declaration of functions #####

# Function to clear the screen
function clear_screen() {
    clear
}

# Function to check if the .env file exists
function check_env() {
    if [ ! -f ${SCRIPT_PATH}/.env ]
    then
        echo "Creating .env file..."
        touch ${SCRIPT_PATH}/.env
        echo "AWS_ACCESS_KEY_ID=S3-USER
AWS_SECRET_ACCESS_KEY=S3-PASSWORD
RESTIC_REPOSITORY=s3:http://127.0.0.1:9000/bucket-name
RESTIC_PASSWORD=REPO-PASSWORD
KEEP_DAYS=30" > ${SCRIPT_PATH}/.env
        echo "Please edit the .env file next to the script and run the script again"
        read -p "Press ENTER to continue..." dummy
        exit
    fi
}

# Function to check if restic is installed
function check_restic() {
    if ! command -v restic &> /dev/null
    then
        restic_installed="${RED}NOT INSTALLED${NC}"
    else
        restic_installed="${GREEN}INSTALLED${NC}"
    fi
}

# Function to check if the user is root
function check_root() {
    if [ "$EUID" -ne 0 ]
    then
        echo "Please run script as root"
        exit
    fi
}

# Function to check the repository and connection
function check_repository() {
    echo "Checking repository integrity..."
    restic check
}

# Function to initialize the repository
function initialize_repository() {
    echo "Initializing repository..."
    restic init
}

# Function to prune the repository
function prune_repository() {
    echo "Pruning repository..."
    restic prune
}

# Function to be executed by crontab as weekly runner to backup the whole system
function weekly_backup() {
    echo "Weekly backup..."

    # Set the lockfile
    LOCKFILE=${SCRIPT_PATH}/.backup-lock

    # Create the lockfile if it doesn't exist
    if [ ! -f ${LOCKFILE} ]
    then
        touch ${LOCKFILE}
    fi

    # Check if the lockfile exists and read the date from it
    if [ -f ${LOCKFILE} ]
    then
        # Get the date from the lockfile and convert it to a timestamp
        LOCKFILE_DATE=$(cat ${LOCKFILE})
        # Format the date from the lockfile to a timestamp in seconds since 1970-01-01 00:00:00 UTC
        LOCKFILE_TIMESTAMP=$(date -d ${LOCKFILE_DATE} +%s)
        # Get the current date and convert it to a timestamp in seconds since 1970-01-01 00:00:00 UTC
        CURRENT_DATE=$(date +%s)
        # Calculate the difference between the current date and the date from the lockfile in seconds
        DIFFERENCE=$CURRENT_DATE - $LOCKFILE_TIMESTAMP
        # Calculate the difference between the current date and the date from the lockfile in days
        DIFFERENCE_DAYS=$(($DIFFERENCE / (60 * 60 * 24)))


        # Compare the date from the lockfile with the current date
        if [ "${DIFFERENCE_DAYS}" -lt 7 ]
        then
            echo "Backup already executed this week"
            exit 0
        fi
    fi

    backup_whole_system

    # Write the current date to the lockfile
    echo "$(date +%Y-%m-%d)" > ${LOCKFILE}
}

# Function to be executed by crontab as daily runner to backup the whole system
function daily_backup() {
    echo "Daily backup..."

    # Set the lockfile
    LOCKFILE=${SCRIPT_PATH}/.backup-lock

    # Create the lockfile if it doesn't exist
    if [ ! -f ${LOCKFILE} ]
    then
        touch ${LOCKFILE}
    fi

    # Check if the lockfile exists and read the date from it
    if [ -f ${LOCKFILE} ]
    then
        LOCKFILE_DATE=$(cat ${LOCKFILE})

        # Compare the date from the lockfile with the current date
        if [ "${LOCKFILE_DATE}" == "$(date +%Y-%m-%d)" ]
        then
            echo "Backup already executed today"
            exit 0
        fi
    fi

    backup_whole_system

    # Write the current date to the lockfile
    echo "$(date +%Y-%m-%d)" > ${LOCKFILE}
}

# Function to backup the whole system
function backup_whole_system() {
    echo "Backing up whole system..."
    restic --exclude={/dev,/media,/mnt,/proc,/run,/sys,/tmp,/var/tmp,/timeshift} backup /
}

# Function to backup specific directories or files
function backup_specific() {
    echo "Backing up specific directory or file..."
    if [ -n "$2" ]
    then
        restic backup $2
        exit 0
    else
        read -p "Please enter the directory or file (Full Path only) to backup: " directories
        restic backup $directories
    fi
}

# Function to list snapshots
function list_snapshots() {
    echo "Listing snapshots..."
    restic snapshots
}

# Function to forget snapshots older then ${KEEP_DAYS} days
function forget_snapshots() {
    echo "Forgetting snapshots older then ${KEEP_DAYS} days..."
    restic forget --keep-within ${KEEP_DAYS}d
}

# Function to mount the repository
function mount_repository() {
    if [ -n "$2" ]
    then
        echo -e "The repository will be mounted at ${BLUE}${2}${NC} please ${RED}leave the terminal open${NC}"
        restic mount $2 --allow-other
        umount -f $2
        exit 0
    else
        read -p "Please enter the mount point (Full Path only) to mount the repository: " mount_point
        echo -e "The repository will be mounted at ${BLUE}${mount_point}${NC} please ${RED}leave the terminal open${NC}"
        echo "Mounting repository..."
        restic mount ${mount_point} --allow-other
        umount -f ${mount_point}
    fi
}

# Function to schedule backup
function schedule_backup() {
    echo "Scheduling backup..."

    # Ask if the user wants to schedule a weekly or daily backup
    read -p "Do you want to schedule a weekly or daily backup? (w/d): " schedule
    case $schedule in
        [Ww]* ) JOB="@reboot ${SCRIPT_PATH}/$(basename $0) weekly-backup";;
        [Dd]* ) JOB="@reboot ${SCRIPT_PATH}/$(basename $0) daily-backup";;
        * ) echo "Please answer with w or d"; exit;;
    esac

    # Check if the cronjob already exists
    if crontab -l | grep -q "$JOB"
    then
        echo "Cronjob already exists"
    else
        # Add the cronjob
        (crontab -l 2>/dev/null; echo "$JOB") | crontab -
        echo "Cronjob added"
    fi
}

# Function to schedule forget snapshots
function schedule_forget() {
        # Ask if the user wants to schedule a weekly or daily forget
    read -p "Do you want to schedule a weekly or daily forget? (w/d): " schedule
    case $schedule in
        [Ww]* ) JOB="@reboot ${SCRIPT_PATH}/$(basename $0) weekly-forget";;
        [Dd]* ) JOB="@reboot ${SCRIPT_PATH}/$(basename $0) daily-forget";;
        * ) echo "Please answer with w or d"; exit;;
    esac

    # Check if the cronjob already exists
    if crontab -l | grep -q "$JOB"
    then
        echo "Cronjob already exists"
    else
        # Add the cronjob
        (crontab -l 2>/dev/null; echo "$JOB") | crontab -
        echo "Cronjob added"
    fi
}

# Function to be executed by crontab as daily runner to forget snapshots older then ${KEEP_DAYS} days
function daily_forget() {
    echo "Daily forget..."

    # Set the lockfile
    LOCKFILE=${SCRIPT_PATH}/.forget-lock

    # Create the lockfile if it doesn't exist
    if [ ! -f ${LOCKFILE} ]
    then
        touch ${LOCKFILE}
    fi

    # Check if the lockfile exists and read the date from it
    if [ -f ${LOCKFILE} ]
    then
        LOCKFILE_DATE=$(cat ${LOCKFILE})

        # Compare the date from the lockfile with the current date
        if [ "${LOCKFILE_DATE}" == "$(date +%Y-%m-%d)" ]
        then
            echo "Forget already executed today"
            exit 0
        fi
    fi

    restic forget --keep-within ${KEEP_DAYS}d

    # Write the current date to the lockfile
    echo "$(date +%Y-%m-%d)" > ${LOCKFILE}
}

# Function to be executed by crontab as weekly runner to forget snapshots older then ${KEEP_DAYS} days
function weekly_forget() {
    echo "Weekly forget..."

    # Set the lockfile
    LOCKFILE=${SCRIPT_PATH}/.forget-lock

    # Create the lockfile if it doesn't exist
    if [ ! -f ${LOCKFILE} ]
    then
        touch ${LOCKFILE}
    fi

    # Check if the lockfile exists and read the date from it
    if [ -f ${LOCKFILE} ]
    then
        # Get the date from the lockfile and convert it to a timestamp
        LOCKFILE_DATE=$(cat ${LOCKFILE})
        # Format the date from the lockfile to a timestamp in seconds since 1970-01-01 00:00:00 UTC
        LOCKFILE_TIMESTAMP=$(date -d ${LOCKFILE_DATE} +%s)
        # Get the current date and convert it to a timestamp in seconds since 1970-01-01 00:00:00 UTC
        CURRENT_DATE=$(date +%s)
        # Calculate the difference between the current date and the date from the lockfile in seconds
        DIFFERENCE=$CURRENT_DATE - $LOCKFILE_TIMESTAMP
        # Calculate the difference between the current date and the date from the lockfile in days
        DIFFERENCE_DAYS=$(($DIFFERENCE / (60 * 60 * 24)))


        # Compare the date from the lockfile with the current date
        if [ "${DIFFERENCE_DAYS}" -lt 7 ]
        then
            echo "Forget already executed this week"
            exit 0
        fi
    fi

    restic forget --keep-within ${KEEP_DAYS}d

    # Write the current date to the lockfile
    echo "$(date +%Y-%m-%d)" > ${LOCKFILE}
}

# Function to unlock the repository
function unlock_repository() {
    echo "Unlocking repository..."
    restic unlock --remove-all
}

# Function to install restic
function install_restic() {
    if [ ! -f /bin/restic ]
    then
        echo "Installing restic..."

        # Set the github repository and release information
        REPO_OWNER="restic"
        REPO_NAME="restic"
        RELEASE_TAG="latest"

        # Get the release information using the GitHub API
        release_info=$(curl -s "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/$RELEASE_TAG")

        # Extract the download URL for the binary asset
        download_url=$(echo "$release_info" | grep "browser_download_url" | grep "linux_amd64" | head -n 1 | cut -d '"' -f 4)

        # Extract the filename of the binary asset
        file_name=$(basename "$download_url")

        # Download the binary asset
        curl -LJO "$download_url"

        # Extract the binary from the bz2 archive
        bzip2 -d $file_name

        # Move the binary to /bin/restic
        binary_filename=$(basename $file_name .bz2)
        mv $binary_filename /bin/restic

        # Make the binary executable for all users
        chmod a+x /bin/restic

        echo "restic is now INSTALLED"
    else
        echo "restic is already INSTALLED"
    fi
}

# Function to uninstall restic
function uninstall_restic() {
    if [ -f /bin/restic ]
    then
        echo "Uninstalling restic.."
        rm /bin/restic
        echo "restic is now UNINSTALLED"
    else
        echo "restic is NOT INSTALLED"
    fi
}

# Function make the .env information available for restic
function export_env_info() {
    export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
    export RESTIC_REPOSITORY=$RESTIC_REPOSITORY
    export RESTIC_PASSWORD=$RESTIC_PASSWORD
}

# Function to handle the ui input
function handle_ui_input() {
    read -p "Enter your choice: " selection
    execute_function $selection
}

# Function to have colors as variables
function set_colors() {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
}

# Function to display the menu
function display_menu() {
    # clear_screen
    echo -e ""
    echo -e "██████╗ ███████╗███████╗████████╗██╗ ██████╗    ████████╗██╗   ██╗██╗"
    echo -e "██╔══██╗██╔════╝██╔════╝╚══██╔══╝██║██╔════╝    ╚══██╔══╝██║   ██║██║"
    echo -e "██████╔╝█████╗  ███████╗   ██║   ██║██║            ██║   ██║   ██║██║"
    echo -e "██╔══██╗██╔══╝  ╚════██║   ██║   ██║██║            ██║   ██║   ██║██║"
    echo -e "██║  ██║███████╗███████║   ██║   ██║╚██████╗       ██║   ╚██████╔╝██║"
    echo -e "╚═╝  ╚═╝╚══════╝╚══════╝   ╚═╝   ╚═╝ ╚═════╝       ╚═╝    ╚═════╝ ╚═╝"
    echo -e "                                                                  pk7"
    check_restic
    echo -e "restic is ${restic_installed}"
    echo -e "repository used: ${YELLOW}${RESTIC_REPOSITORY}${NC}"
    echo -e "backups will be forgotten after ${RED}${KEEP_DAYS}${NC} days"
    echo -e ""
    echo -e "| ---------- ${BLUE}INSTALL${NC} ---------------------------------------------- |"
    echo -e "| [1]  Install restic                                               |"
    echo -e "| [2]  Uninstall restic                                             |"
    echo -e "| ---------- ${BLUE}MAINTENANCE${NC} ------------------------------------------ |"
    echo -e "| [3]  Initialize repository                                        |"
    echo -e "| [4]  Check repository integrity                                   |"
    echo -e "| [5]  Prune repository (Remove unused data)                        |"
    echo -e "| [6]  Unlock repository                                            |"
    echo -e "| ---------- ${BLUE}BACKUP${NC} ----------------------------------------------- |"
    echo -e "| [7]  Backup whole system                                          |"
    echo -e "| [8]  Backup specific folder or file                               |"
    echo -e "| ---------- ${BLUE}DELETE${NC} ----------------------------------------------- |"
    echo -e "| [9]  Forget snapshots older then KEEP_DAYS from .env              |"
    echo -e "| ---------- ${BLUE}RESTORE${NC} ---------------------------------------------- |"
    echo -e "| [10] Mount repository                                             |"
    echo -e "| [11] List snapshots                                               |"
    echo -e "| ---------- ${BLUE}SCHEDULE${NC} --------------------------------------------- |"
    echo -e "| [12] Schedule whole system backup (weekly/daily)                  |"
    echo -e "| [13] Schedule forget (weekly/daily)                               |"
    echo -e "| ----------------------------------------------------------------- |"
}

# Function to execute the corresponding function
function execute_function() {
    case $1 in
        1) install_restic ;;
        2) uninstall_restic ;;
        3) initialize_repository ;;
        4) check_repository ;;
        5) prune_repository ;;
        6) unlock_repository ;;
        7) backup_whole_system ;;
        8) backup_specific $@ ;;
        9) forget_snapshots ;;
        10) mount_repository $@ ;;
        11) list_snapshots ;;
        12) schedule_backup ;;
        13) schedule_forget ;;
        daily-backup) daily_backup ;;
        weekly-backup) weekly_backup ;;
        daily-forget) daily_forget ;;
        weekly-forget) weekly_forget ;;
        *) echo "Invalid choice" ;;
    esac
}

##### Start of the script #####

# Create Variable for the script path
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)"

# Check for root and env variables
check_root
check_env

# Load the .env file and export the variables for restic
source ${SCRIPT_PATH}/.env
export_env_info

# Set colors
set_colors

# If restic.sh is run with a number parameter, it will run the corresponding function
if [ $# -ge 1 ]
then
    execute_function $@
    exit 0
fi

# Main loop if no parameter is given
while true; do
    # clear_screen
    display_menu
    handle_ui_input
    read -p "Press ENTER to continue..." dummy
done
