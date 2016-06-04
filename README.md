# eyga-backup-bash
==================

Backup script for MySQL databases and Linux user files.
Full MySQL backup is created once per day and diffs are created on every hour.
Linux user files are backed up once per week and diffs are created every day.

Uses TAR for compression.

Installation and configuration:
- open all .conf and .sh files and adjust the settings at the top of the files
- add a cron/job schedule to run backup-full.py once per day
- add a cron/job schedule to run backup-diff.py once per hour
