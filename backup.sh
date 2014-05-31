#!/bin/bash
#
# Argument = -u user -p password -k key -s secret -b bucket
#
# To Do - Add logging of output.
# To Do - Abstract bucket region to options

set -e

export PATH="$PATH:/usr/local/bin"

usage()
{
cat << EOF
usage: $0 options

This script dumps the current mongo database, tars it, then sends it to an Amazon S3 bucket.

OPTIONS:
   -help   Show this message
   -u      Mongodb user
   -p      Mongodb password
   -h      Mongodb host
   -port   Mongodb port
   -k      AWS Access Key
   -s      AWS Secret Key
   -r      Amazon S3 region
   -b      Amazon S3 bucket name
EOF
}

MONGODB_HOST=
MONGODB_PORT=
MONGODB_USER=
MONGODB_PASSWORD=
AWS_ACCESS_KEY=
AWS_SECRET_KEY=
S3_REGION=
S3_BUCKET=

while getopts “h:m:u:p:k:s:r:b:port” OPTION
do
  echo $OPTION
  case $OPTION in
    h)
      MONGODB_HOST=$OPTARG
      ;;
    m)
      MONGODB_PORT=$OPTARG
      ;;
    u)
      MONGODB_USER=$OPTARG
      ;;
    p)
      MONGODB_PASSWORD=$OPTARG
      ;;
    k)
      AWS_ACCESS_KEY=$OPTARG
      ;;
    s)
      AWS_SECRET_KEY=$OPTARG
      ;;
    r)
      S3_REGION=$OPTARG
      ;;
    b)
      S3_BUCKET=$OPTARG
      ;;
  esac
done

if [[ -z $AWS_ACCESS_KEY ]] || [[ -z $AWS_SECRET_KEY ]] || [[ -z $S3_REGION ]] || [[ -z $S3_BUCKET ]]
then
  echo $AWS_ACCESS_KEY
  usage
  exit 1
fi

# Get the directory the script is being run from
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echo $DIR
# Store the current date in YYYY-mm-DD-HHMMSS
DATE=$(date -u "+%F-%H%M%S")
FILE_NAME="backup-$DATE"
ARCHIVE_NAME="$FILE_NAME.tar.gz"

# Dump the database
if [[ -n "$MONGODB_USER" ]] && [[ -n "$MONGODB_PASSWORD" ]]
then
  mongodump --username "$MONGODB_USER" --password "$MONGODB_PASSWORD" --authenticationDatabase "admin" --host "$MONGODB_HOST:$MONGODB_PORT" --out $DIR/backup/$FILE_NAME
else
  mongodump --host "$MONGODB_HOST" --out $DIR/backup/$FILE_NAME
fi

# Tar Gzip the file
tar -C $DIR/backup/ -zcvf $DIR/backup/$ARCHIVE_NAME $FILE_NAME/

# Remove the backup directory
rm -r $DIR/backup/$FILE_NAME

# Send the file to the backup drive or S3

HEADER_DATE=$(date -u "+%a, %d %b %Y %T %z")
CONTENT_MD5=$(openssl dgst -md5 -binary $DIR/backup/$ARCHIVE_NAME | openssl enc -base64)
CONTENT_TYPE="application/x-download"
STRING_TO_SIGN="PUT\n$CONTENT_MD5\n$CONTENT_TYPE\n$HEADER_DATE\n/$S3_BUCKET/$ARCHIVE_NAME"
SIGNATURE=$(echo -e -n $STRING_TO_SIGN | openssl dgst -sha1 -binary -hmac $AWS_SECRET_KEY | openssl enc -base64)

curl -X PUT \
--header "Host: $S3_BUCKET.s3-$S3_REGION.amazonaws.com" \
--header "Date: $HEADER_DATE" \
--header "content-type: $CONTENT_TYPE" \
--header "Content-MD5: $CONTENT_MD5" \
--header "Authorization: AWS $AWS_ACCESS_KEY:$SIGNATURE" \
--upload-file $DIR/backup/$ARCHIVE_NAME \
https://$S3_BUCKET.s3-$S3_REGION.amazonaws.com/$ARCHIVE_NAME