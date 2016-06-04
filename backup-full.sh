#!/bin/bash
source "$(dirname $0)/backup.conf"

# Settings
hmd="/home" # Location of home direcotry
bak="/home/backup-full" # Location of backup files
tmp="/home/backup-full-tmp" # Location of temporary files
sql="mysqldump" # MySQL dump files for diffs

# Ignore databases
dbi="mysql|information_schema|performance_schema|user2_database1|user2_database2"

# Files: user, ignore list (separated by pipe)
fil=( "user1" "" \
      "user2" "user2/www/domain1.com|user2/www/domain2.com|*.avi|*.mpg|*.MPG|*.mpeg|*.wmv" )

########
# Code #
########

# For syntax testing
if [ "$1" == "test" ]; then
  exit
fi

# Check the existence of directories
if [ ! -d "$tmp/$sql" ]; then
  mkdir "$tmp/$sql" -p -m 600
fi

# Defining the type of backup
if [ $(date +"%u") == "6" ]; then # Saturday
  # Weekly backup
  typ="w"
  dat=$(( `echo $(date --date="-50 minutes" +"%V") | sed "s/0*//"` % 4 + 1 )) # Last 4 weeks
else
  # Daily backup
  typ="d"
  dat=$(date --date="-50 minutes" +"%u") # Last 7 days
fi

# Dump and compress databases
rm $tmp/$sql/* -f
mysqldump --compress --skip-extended-insert $sba --no-create-info --databases mysql --tables db user \
  | sed "17s/^$/\nUSE \`mysql\`;\n/" \
  | grep --invert-match --extended-regexp "^INSERT INTO \`user\` VALUES \('(\w|\-|\.)*','(root|debian-sys-maint)'," \
  > $tmp/$sql/mysqlaccess.sql
echo "FLUSH PRIVILEGES;" \
  >> $tmp/$sql/mysqlaccess.sql
echo "mysql -u root -p < mysqlaccess.sql" \
  > $tmp/$sql/mysqlimport.sh
chmod +x $tmp/$sql/mysqlimport.sh
dbl=`find /var/lib/mysql -mindepth 1 -type d -printf "%f\n" | grep -vE "^($dbi)$" | sort | sed "s/ $//"`
for db in $dbl; do
  mysqldump --compress --skip-extended-insert $sba --databases $db \
    > $tmp/$sql/$db.sql
  echo "mysql -u root -p < $db.sql" \
    >> $tmp/$sql/mysqlimport.sh
done
# Compress files
tar -c -z -C $tmp $sql \
  | openssl enc -aes-128-cbc -salt -pass pass:$bpa -out $bak/$sql-$typ$dat.tar.gz.aes
rm $tmp/$sql/* -f

# Weekly database optimizations
if [ $typ == "w" ]; then
  mysqloptimize --compress --silent $sop --databases $dbl \
    >> $bak/mysqloptimize.log
fi

# Weekly file backup
if [ $typ == "w" ]; then
  # For every user
  for (( i=0; i<${#fil[@]}; i=i+2 )); do
    # Variables
    usr=${fil[$i+0]} # User
    igl=${fil[$i+1]} # Ignore list
    # Ignore parameters
    if [ "$igl" == "" ]; then
      igp=""
    else
      igp="--exclude="`echo "$igl" | sed "s/|/ --exclude=/g"`
    fi
    # Compress files
    tar -c -z -C $hmd $igp $usr \
      | openssl enc -aes-128-cbc -salt -pass pass:$bpa -out $bak/$usr-$typ$dat.tar.gz.aes
  done
fi

