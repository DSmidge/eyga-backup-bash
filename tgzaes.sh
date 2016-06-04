#!/bin/bash
if [ "$1" != "-x" ] && [ "$1" != "-t" ]; then
  echo "Unencrypt and uncompress: (-x | -t) file pass"
else
  openssl enc -d -aes-128-cbc -salt -in $2 -pass pass:$3 | tar -z $1
fi
