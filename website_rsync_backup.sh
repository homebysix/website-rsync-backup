#!/bin/bash

###
#
#            Name:  website_rsync_backup.sh
#     Description:  Easily and automatically backs up the files on your web host
#                   to your local computer. This script is meant to be executed
#                   once per day using cron.
#          Author:  Elliot Jordan <elliot@elliotjordan.com>
#         Created:  2014-12-12
#   Last Modified:  2014-12-20
#         Version:  1.0.1
#
###


############################### WEBSITE SETTINGS ###############################

# The name or URL of your website(s).
# No https:// and no trailing slash.
WEBSITE_NAME=(
    "www.pretendco.com"
    "shop.pretendco.com"
)

# The hostname of the website. Might be the same as the domain name.
# You must have SSH keys configured for automatic connection to this host.
WEBSITE_HOST=(
    "www.pretendco.com"
    "shop.pretendco.com"
)

# The path on the web server that you want to back up locally.
# Defaults to ~ (home folder). No trailing slash.
BACKUP_SOURCE=(
    "~"
    "~"
)

# The path on your local computer that you want to back up to.
# No trailing slash.
BACKUP_DEST=(
    "/Backups/pretendco.com"
    "/Backups/shop.pretendco.com"
)

# Path to exclusion file, if you'd like to exclude certain items from backup.
# See the included example: exclusions.txt
EXCLUDE_FILE=(
    "/Backups/pretendco.com/exclusions.txt"
    "/Backups/shop.pretendco.com/exclusions.txt"
)

# The full path to the file(s) you'd like to save log output to.
# I recommend NOT saving this log file inside your WEBSITE_ROOT dir.
# You can use the same log for multiple sites.
LOG_FILE="/var/log/website_rsync_backup.log"

# Type of compression you'd like to use to shrink the files on the destination.
# Acceptable values are "dmg" (Mac only), "zip", "tar-gz", or "none".
COMPRESSION="none"


################################ ALERT SETTINGS ################################

# Set to true if you'd like to receive alerts via SMS upon plugin count change.
SEND_SMS_ALERT_ON_ERROR=false
# If the above is true, specify your phone's email-to-txt address here.
SMS_RECIPIENT="0005551212@txt.att.net"

# Set to true if you'd like to receive an email when the backup succeeds.
SEND_EMAIL_ON_SUCCESS=false
# Set to true if you'd like to receive an email when the backup fails.
SEND_EMAIL_ON_ERROR=true

# The email notifications will be sent to this email address.
# Multiple "to" addresses can be separated by commas.
EMAIL_TO="you@pretendco.com, somebodyelse@pretendco.com"

# The email notifications will be sent from this email address.
EMAIL_FROM="$(whoami)@$(hostname)"

# The path to sendmail on your server. Typically /usr/sbin/sendmail.
sendmail="/usr/sbin/sendmail"

# Format of the datestamp that will be used to mark files and folders.
DATESTAMP="$(date +%Y-%m-%d)"

# Set to true if you want to display email and SMS mesages as output rather than
# actually sending them. Also displays extra messages during rsync.
DEBUG_MODE=false


################################################################################
######################### DO NOT EDIT BELOW THIS LINE ##########################
################################################################################


################################## FUNCTIONS ###################################

# Log functions
APPNAME=$(basename "$0" | sed "s/\.sh$//")
fn_log_info() {
    echo "$(date) : $APPNAME : $1" >> "$LOG_FILE"
}
fn_log_debug() {
    echo "$(date) : $APPNAME : [DEBUG] $1" >> "$LOG_FILE"
}
fn_log_warn() {
    echo "$(date) : $APPNAME : [WARNING] $1" >> "$LOG_FILE"
    echo "$(date) : $APPNAME : [WARNING] $1" 1>&2
}
fn_log_error() {
    echo "$(date) : $APPNAME : [ERROR] $1" >> "$LOG_FILE"
    echo "$(date) : $APPNAME : [ERROR] $1" 1>&2
}

# Make sure the whole script stops if Control-C is pressed.
fn_terminate() {
    fn_log_error "Script $APPNAME terminated by shell user."
    exit 1001
}
trap 'fn_terminate' SIGINT


######################## VALIDATION AND ERROR CHECKING #########################

printf "\n --- Begin %s --- \n\n" "$APPNAME" >> "$LOG_FILE"

# Set up ditto arguments. If DEBUG_MODE is on, we need it to be more verbose.
if [[ $DEBUG_MODE == true ]]; then
    V="-v"
    VERBOSE="--verbose --human-readable"
    fn_log_debug "Debug mode is on.\n"
elif [[ $DEBUG_MODE == false ]]; then
    #statements
    QUIET="-quiet"
    Q="-q"
else
    fn_log_warn "DEBUG_MODE should be set to true or false."
    QUIET="-quiet"
    Q="-q"
fi

# Let's make sure we have the same number of website settings.
if [[ ${#WEBSITE_NAME[@]} != ${#WEBSITE_HOST[@]} ||
      ${#WEBSITE_NAME[@]} != ${#BACKUP_SOURCE[@]} ||
      ${#WEBSITE_NAME[@]} != ${#BACKUP_DEST[@]} ||
      ${#WEBSITE_NAME[@]} != ${#EXCLUDE_FILE[@]} ]]; then

    echo "ERROR: Please carefully check the website settings in the $APPNAME script. The number of parameters don't match." >&2
    exit 1002

fi # End website settings count validation.

# Let's make sure we aren't using default email alert settings.
if [[ $EMAIL_TO == "you@pretendco.com, somebodyelse@pretendco.com" ]]; then

    echo "ERROR: The email alert settings are still set to the default value. Please edit them to suit your environment." >&2
    exit 1003

fi # End email settings validation.

# Let's make sure we aren't using default SMS alert settings.
if [[ $SEND_SMS_ALERT_ON_ERROR == true &&
      $SMS_RECIPIENT == "0005551212@txt.att.net" ]]; then

    echo "ERROR: The SMS alert settings are still set to the default value. Please edit them to suit your environment." >&2
    exit 1004

fi # End SMS settings validation.

# Let's make sure the sendmail path is correct.
if [[ ! -x $sendmail ]]; then

    fn_log_warn "The specified path to sendmail ($sendmail) appears to be incorrect. Trying to locate the correct path..."
    sendmail_try2=$(which sendmail)

    if [[ $sendmail_try2 == '' || ! -x $sendmail_try2 ]]; then
        echo "ERROR: Unable to locate the path to sendmail." >&2
        exit 1005
    else
        echo "Located sendmail at $sendmail_try2. Please adjust the \"$APPNAME\" script settings accordingly." >&2
        sendmail="$sendmail_try2"
        # Fatal error avoided. No exit needed.
    fi

fi # End sendmail validation.


################################# MAIN PROCESS #################################

# Count the number of sites we need to process.
SITE_COUNT=${#WEBSITE_NAME[@]}

# Begin iterating through websites.
for (( i = 0; i < SITE_COUNT; i++ )); do

    fn_log_info "Started backing up ${WEBSITE_NAME[$i]} ($((i+1)) of $SITE_COUNT)."
    fn_log_info "Destination: ${BACKUP_DEST[$i]}"

    # If the exclusions file doesn't exist, create a blank one.
    if [[ ! -f "${EXCLUDE_FILE[$i]}" ]]; then
        echo "# No exclusions for ${WEBSITE_NAME[$i]}." >> "${EXCLUDE_FILE[$i]}"
    fi

    # See what folders already exist, and whether they can be reused for efficiency.
    if [[ ! -d "${BACKUP_DEST[$i]}" ]]; then

        # A folder doesn't already exist at our destination, so we'll create it.
        fn_log_info "Creating destination folder..."
        mkdir -p "${BACKUP_DEST[$i]}"

    else # A folder already exists at our destination.

        # Check for an earlier backup from today.
        if [[ -d "${BACKUP_DEST[$i]}"/"$DATESTAMP"_in_progress_rsync ||
              -d "${BACKUP_DEST[$i]}"/"$DATESTAMP"_latest_rsync ||
              -d "${BACKUP_DEST[$i]}"/"$DATESTAMP"_rsync ]]; then

            if [[ -d "${BACKUP_DEST[$i]}"/"$DATESTAMP"_in_progress_rsync &&
                  ! -d "${BACKUP_DEST[$i]}"/"$DATESTAMP"_latest_rsync &&
                  ! -d "${BACKUP_DEST[$i]}"/"$DATESTAMP"_rsync ]]; then
                
                # In-progress backup is the only one that exists, so we'll use that folder.
                fn_log_info "Will perform incremental rsync using an unfinished backup from earlier today."

            elif [[ ! -d "${BACKUP_DEST[$i]}"/"$DATESTAMP"_in_progress_rsync &&
                    -d "${BACKUP_DEST[$i]}"/"$DATESTAMP"_latest_rsync &&
                    ! -d "${BACKUP_DEST[$i]}"/"$DATESTAMP"_rsync ]]; then
                
                # Latest backup is the only one that exists, so we'll rename that to in-progress.
                mv "${BACKUP_DEST[$i]}"/"$DATESTAMP"_latest_rsync "${BACKUP_DEST[$i]}"/"$DATESTAMP"_in_progress_rsync
                fn_log_info "Will perform incremental rsync using the latest backup from today."

            elif [[ ! -d "${BACKUP_DEST[$i]}"/"$DATESTAMP"_in_progress_rsync &&
                    ! -d "${BACKUP_DEST[$i]}"/"$DATESTAMP"_latest_rsync &&
                    -d "${BACKUP_DEST[$i]}"/"$DATESTAMP"_rsync ]]; then
                
                # Previous backup is the only one that exists, so we'll rename that to in-progress.
                mv "${BACKUP_DEST[$i]}"/"$DATESTAMP"_rsync "${BACKUP_DEST[$i]}"/"$DATESTAMP"_in_progress_rsync
                fn_log_info "Will perform incremental rsync using a previous backup from today."

            else

                # Multiple backups from today exist. A merge is needed.
                mkdir "${BACKUP_DEST[$i]}"/"$DATESTAMP"_merge_rsync
                fn_log_info "Cleaning up backups from earlier today..."

                # Merge, overwriting older backups with newer backups. Ignore errors.
                ditto $V "${BACKUP_DEST[$i]}"/"$DATESTAMP"_rsync "${BACKUP_DEST[$i]}"/"$DATESTAMP"_merge_rsync 2> /dev/null
                ditto $V "${BACKUP_DEST[$i]}"/"$DATESTAMP"_latest_rsync "${BACKUP_DEST[$i]}"/"$DATESTAMP"_merge_rsync 2> /dev/null
                ditto $V "${BACKUP_DEST[$i]}"/"$DATESTAMP"_in_progress_rsync "${BACKUP_DEST[$i]}"/"$DATESTAMP"_merge_rsync 2> /dev/null

                # Remove today's old backups.
                rm -rf "${BACKUP_DEST[$i]}"/"$DATESTAMP"_rsync
                rm -rf "${BACKUP_DEST[$i]}"/"$DATESTAMP"_latest_rsync
                rm -rf "${BACKUP_DEST[$i]}"/"$DATESTAMP"_in_progress_rsync

                # Rename the merge folder so it can be used for incremental rsync.
                mv "${BACKUP_DEST[$i]}"/"$DATESTAMP"_merge_rsync "${BACKUP_DEST[$i]}"/"$DATESTAMP"_in_progress_rsync
                fn_log_info "Will perform incremental rsync using a merged version of today's backups."

            fi

        else # No backup exists from today, so let's check for backups from previous days.

            # If unfinished backups from previous days exist, there's probably something wrong.
            UNFINISHED_BACKUPS=$(find "${BACKUP_DEST[$i]}" -type d -maxdepth 1 -name "*_in_progress_rsync")
            if [[ ! -z "$UNFINISHED_BACKUPS" ]]; then
                fn_log_warn "There are unfinished rsync backups present in the backup destination:\n$UNFINISHED_BACKUPS"
            fi

            # Check for the "latest" backup.
            # This backup is intentionally left for reuse by previous script runs.
            PREVIOUS_BACKUP=$(find "${BACKUP_DEST[$i]}" -type d -maxdepth 1 -name "????-??-??_latest_rsync" | sort -r | head -1)

            if [[ ! -z "$PREVIOUS_BACKUP" ]]; then

                # "Latest" backup exists. Update its datestamp.
                fn_log_info "Found latest backup: $PREVIOUS_BACKUP"
                fn_log_info "Moving latest backup to new datestamped folder..."
                mv "$PREVIOUS_BACKUP" "${BACKUP_DEST[$i]}"/"$DATESTAMP"_in_progress_rsync
                fn_log_info "Move complete. Will perform incremental rsync using latest backup."

            else

                # No "latest" backup exists, so check for the most recent previous backup.
                # These backups are usually only present if compression is turned off.
                PREVIOUS_BACKUP=$(find "${BACKUP_DEST[$i]}" -type d -maxdepth 1 -name "????-??-??_rsync" | sort -r | head -1)

                if [[ ! -z "$PREVIOUS_BACKUP" ]]; then

                    # Previous backup exists. Copy it to a new datestamped backup.
                    fn_log_info "Found previous backup: $PREVIOUS_BACKUP"
                    fn_log_info "Duplicating previous backup to new datestamped folder..."
                    mkdir -p "${BACKUP_DEST[$i]}"/"$DATESTAMP"_in_progress_rsync
                    ditto $V "$PREVIOUS_BACKUP" "${BACKUP_DEST[$i]}"/"$DATESTAMP"_in_progress_rsync
                    fn_log_info "Duplication complete. Will perform incremental rsync."

                else

                    # No previous backup exists, so we need to start a new backup.
                    fn_log_warn "Could not determine last backup. Starting next backup from scratch."

                fi # End checking for previous backups.

            fi # End checking for "latest" backup.

        fi # End checking for backup from earlier today.

    fi # End checking for presence of backup destination folder.

    # Use rsync to copy the files from the web host to the local destination folder.
    fn_log_info "Starting rsync copy..."
    rsync --archive --recursive --compress --delete $VERBOSE --exclude-from="${EXCLUDE_FILE[$i]}" \
        "${WEBSITE_HOST[$i]}":"${BACKUP_SOURCE[$i]}/*" "${BACKUP_DEST[$i]}"/"$DATESTAMP"_in_progress_rsync
    if [[ $? -ne 0 ]]; then
        fn_log_warn "The rsync copy of ${WEBSITE_NAME[$i]} encountered errors."
    fi
    mv "${BACKUP_DEST[$i]}"/"$DATESTAMP"_in_progress_rsync "${BACKUP_DEST[$i]}"/"$DATESTAMP"_latest_rsync
    fn_log_info "The rsync copy is done."

    # Set up compression success flag that we'll use later.
    COMPRESSION_OK=false
    cd "${BACKUP_DEST[$i]}"

    # Determine which type of compression is desired, and compress an archive.
    case "$COMPRESSION" in

        "dmg" )

            # Remove existing archives.
            if [[ -f "$DATESTAMP.dmg" ]]; then
                rm "$DATESTAMP.dmg"
            fi
            if [[ -f "$DATESTAMP-inprogress.dmg" ]]; then
                rm "$DATESTAMP-inprogress.dmg"
            fi

            fn_log_info "Compressing to dmg..."
            hdiutil create -format UDZO $QUIET -volname "$DATESTAMP" \
                -srcfolder "$DATESTAMP"_latest_rsync "$DATESTAMP-inprogress.dmg"
            if [[ $? == 0 ]]; then
                COMPRESSION_OK=true
                mv "$DATESTAMP-inprogress.dmg" "$DATESTAMP.dmg"
            fi
            ;;

        "zip" )
            
            # Remove existing archive.
            if [[ -f "$DATESTAMP.zip" ]]; then
                rm "$DATESTAMP.zip"
            fi
            
            fn_log_info "Compressing to zip..."
            zip -r -X $Q "$DATESTAMP".zip "$DATESTAMP"_latest_rsync
            if [[ $? == 0 ]]; then
                COMPRESSION_OK=true
            fi
            ;;

        "tar-gz" )

            # Remove existing archive.
            if [[ -f "$DATESTAMP.tar.gz" ]]; then
                rm "$DATESTAMP.tar.gz"
            fi
            
            fn_log_info "Compressing to tar-gz..."
            tar $V -zcf "$DATESTAMP".tar.gz "$DATESTAMP"_latest_rsync
            if [[ $? == 0 ]]; then
                COMPRESSION_OK=true
            fi
            ;;

        "none" )
            fn_log_info "No compression in use."
            mv "$DATESTAMP"_latest_rsync "$DATESTAMP"_rsync
            COMPRESSION_OK=true
            ;;

        * )
            fn_log_warn "The COMPRESSION setting must be set to zip, dmg, or none. Will skip compression for this round."
            mv "$DATESTAMP"_latest_rsync "$DATESTAMP"_rsync
            ;;

    esac

    # If compression was successful, delete the uncompressed copy of the files.
    if [[ $COMPRESSION_OK == true && $COMPRESSION != "none" ]]; then
        fn_log_info "Compression was successful."
    elif [[ $COMPRESSION_OK == false ]]; then
        fn_log_warn "There was a problem with compression."
    fi

    # Send SMS and email alerts.
    if [[ $ERROR_OCCURRED == true ]]; then
        
        if [[ $SEND_SMS_ALERT_ON_ERROR == true ]]; then

            fn_log_warn "Errors occurred. Sending SMS alert..."
            SMS_MESSAGE="Errors occurred while backing up ${WEBSITE_NAME[$i]}. Details sent to $EMAIL_TO.\n.\n"

            if [[ $DEBUG_MODE == true ]]; then
                # Print the SMS, if in debug mode.
                fn_log_debug "\n\n$SMS_MESSAGE\n\n"
            elif [[ $DEBUG_MODE == false ]]; then
                # Send the SMS.
                printf "%s" "$SMS_MESSAGE" | $sendmail "$SMS_RECIPIENT"
            fi

        fi

        if [[ $SEND_EMAIL_ON_ERROR == true ]]; then

            fn_log_info "Sending email alert..."

            # Write the message.
            EMAIL_SUBJ="[${WEBSITE_NAME[$i]}] Errors occurred during backup"
            EMAIL_MSG="WARNING: One or more errors occurred while backing up ${WEBSITE_NAME[$i]} to ${BACKUP_DEST[$i]} on $(hostname).\n\nPlease refer to the log at $LOG_FILE for details.\n\nThis is an automated message."

            # Assemble the message.
            THE_EMAIL="From: $EMAIL_FROM\nTo: $EMAIL_TO\nSubject: $EMAIL_SUBJ\n$EMAIL_MSG\n.\n"

            if [[ $DEBUG_MODE == true ]]; then
                # Print the message, if in debug mode.
                printf "%s\n\n" "$THE_EMAIL"
            elif [[ $DEBUG_MODE == false ]]; then
                # Send the message.
                printf "%s" "$THE_EMAIL" | $sendmail "$EMAIL_TO"
            fi

        fi

    else

        if [[ $SEND_EMAIL_ON_SUCCESS == true ]]; then

            fn_log_info "Sending email alert..."
            EMAIL_SUBJ="[${WEBSITE_NAME[$i]}] Backup completed successfully"
            EMAIL_MSG="The automatic backup of ${WEBSITE_NAME[$i]} to ${BACKUP_DEST[$i]} on $(hostname) completed successfully.\n\nPlease refer to the log at $LOG_FILE for details.\n\nThis is an automated message."

            # Assemble the message.
            THE_EMAIL="From: $EMAIL_FROM\nTo: $EMAIL_TO\nSubject: $EMAIL_SUBJ\n$EMAIL_MSG\n.\n"

            if [[ $DEBUG_MODE == true ]]; then
                # Print the message, if in debug mode.
                printf "%s\n\n" "$THE_EMAIL"
            elif [[ $DEBUG_MODE == false ]]; then
                # Send the message.
                printf "%s" "$THE_EMAIL" | $sendmail "$EMAIL_TO"
            fi

        fi

    fi # End SMS and email alerts.

    fn_log_info "Finished backing up ${WEBSITE_NAME[$i]}.\n"

done # End iterating through websites.

printf " --- End %s --- \n" "$APPNAME" >> "$LOG_FILE"

exit 0