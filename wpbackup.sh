#!/bin/bash

backupMainDir=$1

if [ -z "$backupMainDir" ]; then
    backupMainDir='/backup/wp'
fi

currentDate=$(date +"%Y_%m_%d")
backupdir="${backupMainDir}/${currentDate}/"
wordpressFileDir='/var/www/wordpress'
webserverServiceName='nginx'
wordpressDatabase='wordpress'
dbUser='root'
dbPassword='wordpress'
maxNrOfBackups=7
fileNameBackupFileDir='wp_dir.tar.gz'

logger -p notice -t wordpress-backup "Wordpress backup script started"

# Check for root
if [ "$(id -u)" != "0" ]
then
	logger -p err -t wordpress-backup "ERROR: This script has to be run as root!"
	exit 1
fi

# Check if backup dir already exists
if [ ! -d "${backupdir}" ]
then
	mkdir -p "${backupdir}"
else
        logger -p err -t wordpress-backup "ERROR: The backup directory ${backupdir} already exists!"
	exit 1
fi

# Backup file directory
logger -p notice -t wordpress-backup "Creating backup of Wordpress file directory..."
tar -I pigz -cpf "${backupdir}/${fileNameBackupFileDir}" -C "${wordpressFileDir}" .

# Backup DB
logger -p notice -t wordpress-backup "Backup Wordpress database..."

xtrabackup --user=$dbUSER --password=$dbPassword --backup --no-timestamp --slave-info --target-dir=$backupdir/db &>>'/var/log/cop.log'
EXITCODE=$?
if [ $EXITCODE != 0 ]
then
    logger -p err -t wordpress-backup "Error backup $EXITCODE"
    exit 1;
fi

xtrabackup --user=$dbUSER --password=$dbPassword --prepare --slave-info --target-dir=$backupdir/db &>>'/var/log/cop.log'
EXITCODE=$?
if [ $EXITCODE != 0 ]
then
    logger -p err -t wordpress-backup "Error backup $EXITCODE"
    exit 1;
fi

tar -I pigz -cpf "${backupdir}/wp_db.tar.gz" -C "$backupdir/db" .
EXITCODE=$?
if [ $EXITCODE != 0 ]
then
    logger -p err -t wordpress-backup "Error tar.gz archive $EXITCODE"
    exit 1;
fi

rm -rf $backupdir/db

# Delete old backups
if [ ${maxNrOfBackups} != 0 ]
then
	nrOfBackups=$(ls -l ${backupMainDir} | grep -c ^d)

	if [[ ${nrOfBackups} > ${maxNrOfBackups} ]]
	then
		logger -p notice -t wordpress-backup "Removing old backups..."
		ls -t ${backupMainDir} | tail -$(( nrOfBackups - maxNrOfBackups )) | while read -r dirToRemove; do
			logger -p notice -t wordpress-backup "${dirToRemove}"
			rm -r "${backupMainDir}/${dirToRemove:?}"
			logger -p notice -t wordpress-backup "Done"
		done
	fi
fi
logger -p notice -t wordpress-backup "Backup created: ${backupdir}"

