Website Rsync Backup
====================

Easily and automatically backs up the files on your web host to your local computer. This script is meant to be executed once per day using cron.


## Features

- Backs up any files you choose from your web host to your local computer.
- Each backup is placed into an individually datestamped folder for simplicity.
- If a previous backup is found, the files are copied locally before rsync runs for increased efficiency.
- Supports sending email and/or SMS alerts upon completion.
- Works with many different web hosts. (Tested on MediaTemple and HostGator.)
- Can back up multiple sites from different hosts all in the same run.
- Easy to configure automatic daily runs using cron.


## Requirements

- Your web hosting account must allow SSH login.
- You must have configured [SSH keys](https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys--2) to allow connection without a password prompt. (If you run this script as root, the SSH keys must be in the root user's home folder too.)
- Your local computer must have rsync installed. (If you're on a Mac, I recommend using [Brew](http://brew.sh/) to [install a more recent version](http://zaiste.net/2012/07/brand_new_rsync_for_osx/) than the one that ships with OS X.)
- Requires enough local disk space to hold three copies of your web host files. (Ideally more than that, of course.)


## Instructions

1. Edit the options in the WEBSITE SETTINGS and ALERT SETTINGS sections to suit your environment.
2. Make the script executable using `chmod +x`.
3. Run the script.

For automatic daily runs, add the script to the [crontab](http://crontab.org/). (Or if you're on a Mac, place the script in `/etc/periodic/daily`. Be sure to leave your Mac on.)


## Known Issues

- Could be more efficient with rsync by keeping the most recent version of the uncompressed backup, then doing an incremental rsync.


## To Do / Roadmap

- Dry-run mode that shows what will happen instead of actually doing it.
- Version pruning, coming soon.


## Acknowledgements

- Thanks to [@laurent22](https://github.com/laurent22) for the logging and terminate trapping functions.
