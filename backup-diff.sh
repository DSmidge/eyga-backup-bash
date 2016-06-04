#!/bin/bash
source "$(dirname $0)/backup.conf"

# Settings
hmd="/home" # Location of home direcotry
bak="/home/backup-diff" # Location of backup files
tmb="/home/backup-diff-tmp" # Location of temporary files
bma="mymailforbackup@domain1.com" # Send backup to mail address
bmm="Backup: $(date +'%F %R')" # Backup mail message

# List of databases: user, database, extra mysqldump parameters
udb=( "user2" "user2_database1" "CALL my_stored_proc();" \
      "user2" "user2_database2" "" )

# List of files: user, directory, extra tar parameters
udf=( "user2" "www/domain1.com" "--exclude=cache/*" \
      "user2" "www/domain2.com" "--exclude={file1.txt,file2.txt}" )

########
# Code #
########

# For syntax testing
if [ "$1" == "test" ]; then
  exit
fi

# Sending mail
send_file_by_mail()
{
  b="7MB"
  n=$(( `du -B $b "$bak/$f" | awk '{ print $1 }'` ))
  if (( $n == 1 )); then
    echo "One file archive." | mutt $bma -s "$bmm" -a "$bak/$f"
  elif (( $n >= 10 )); then
    echo "File is to large." | mutt $bma -s "$bmm"
  else
    # If file is large, split it
    split -b $b -d -a 1 "$bak/$f" "$tmb-tmp/mail/$f."
    for (( j=0; j<$n; j=j+1 )); do
      k=$(( $j + 1 ))
      echo "Archive splitted. Part $k of $n." | mutt $bma -s "$bmm" -a "$tmb-tmp/mail/$f.$j"
      rm "$tmb-tmp/mail/$f.$j"
    done
  fi
}

# Defining the type of backup
if [ $(date +"%H") == "00" ] || [ "$1" == "w"  ] || [ "$1" == "d" ]; then # Midnight
  if [ $(date +"%u") == "1" ] || [ "$1" == "w" ]; then # First day of the week
    # Weekly backup
    typ="w"
    dat=$(( `echo $(date --date="-50 minutes" +"%V") | sed 's/0*//'` % 4 + 1 )) # Last 4 weeks
  else
    # Daily backup
    typ="d"
    dat=$(date --date="-50 minutes" +"%u") # Last 7 days
  fi
else
  # Hourly backup
  typ="h"
  dat=$(date +"%H")
fi

# Check the existence of directories
if [ ! -d "$bak" ]; then
  mkdir "$bak"
fi
if [ ! -d "$tmb-tmp/mail" ]; then
  mkdir "$tmb-tmp/mail" -p -m 600
fi

# Backup databases
for (( i=0; i<${#udb[@]}; i=i+3 )); do
  # Variables
  usr=${udb[$i]} # User
  udn=${udb[$i]}_${udb[$i+1]} # User database name
  udc=${udb[$i+2]} # Execute custom code
  nus=${udb[$i+3]} # Next user

  # Check if daily file exists
  if [ $typ != "h" ] || [ ! -f "$bak-tmp/sql-d/$udn.sql" ]; then
    udt="d"
    dif=""
    tmp="$bak-tmp"
  else
    udt="h"
    dif="-diff"
    tmp="$tmb-tmp"
  fi

  # Create and clean temp directories
  if [ ! -d "$tmp/sql-$udt" ]; then
    mkdir "$tmp/sql-$udt" -p -m 600
  fi

  # Weekly database optimization and custom code execution
  if [ $typ == "w" ]; then
    if [ "$udc" != "" ]; then
      mysql --compress $sop --execute="$udc" $udn
    fi
    mysqloptimize --compress --silent $sop --databases $udn \
      >> $bak/mysqloptimize.log
  fi

  # Full daily backup, store on disk for hourly diff
  if [ $udt == "d" ]; then
    mysqldump --compress --skip-extended-insert $sba --databases $udn \
      > $bak-tmp/sql-d/$udn.sql
  fi

  # Diff hourly backup
  if [ $udt == "h" ]; then
    mysqldump --compress --skip-extended-insert $sba --databases $udn \
      | diff $bak-tmp/sql-d/$udn.sql - > $tmb-tmp/sql-h/$udn.sql.diff
  fi

  # Compress because username has changed or end of array
  if [ $usr != "$nus" ]; then
    # Compress files
    f="$usr-sql-$typ$dat$dif.tar.gz.aes"
    tar -c -z -C $tmp sql-$udt \
      | openssl enc -aes-128-cbc -salt -pass pass:$bpa -out $bak/$f
    #rm "$tmp/sql-$udt/*"
    # Send contents by mail
    if [ $bma != "" ]; then
      send_file_by_mail
    fi
  fi
done

# Exit if hourly backup
if [ $typ == "h" ]; then
  exit
fi

# Backup files
for (( i=0; i<${#udf[@]}; i=i+3 )); do
  # Variables
  usr=${udf[$i]} # User
  usd=${udf[$i+1]} # Directory

  # Store deltas form start of the week
  if [ $typ != "w" ]; then
    udp=${udf[$i+2]}" --newer-mtime="$(date --date="-$(( $dat - 1 )) days" +"%Y-%m-%d")
    dif="-delta"
  else
    udp=${udf[$i+2]}
    dif=""
  fi

  # Compress files
  f="$usr-$usd-$typ$dat$dif.tar.gz.aes"
  f=${f/\//-}
  tar -c -z $udp -C $hmd $usr/$usd \
    | openssl enc -aes-128-cbc -salt -pass pass:$bpa -out $bak/$f
  # Send contents by mail, ignore large weekly backups
  if [ $bma != "" ] && [ $typ != "w" ]; then
    send_file_by_mail
  fi
done

