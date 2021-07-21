#!/bin/bash

if [ "$1" == "--h" ]; then
  echo "With backup directory specified by parameter: ./wprestore.sh <BackupName> <BackupDirectory> (e.g. ./wprestore.sh 2021_07_19 /database/test10/)"
  exit 0
fi

dateRestore=$1
backupMainDir=$2

if [ -z "$backupMainDir" ]; then
    backupMainDir='/backup/wp'
fi

logger -p notice -t wordpress-restore "Backup directory: $backupMainDir"

currentRestoreDir="${backupMainDir}${dateRestore}"
wordpressFileDir='/var/www/wordpress'
webserverServiceName='nginx'
webserverUser='www-data'
wordpressDatabase='wordpress'
dbUser='root'
dbPassword='wordpress'
dbDataDir='/var/lib/mysql'
fileNameBackupFileDir='wp_dir.tar.gz'
fileNameBackupDb='wp_db.tar.gz'

errormessage() { cat <<< "$@" 1>&2; }

# Check if parameter(s) given
if [ $# != "1" ] && [ $# != "2" ]
then
    errormessage "ERROR: No backup name to restore given, or wrong number of parameters!"
    errormessage "Usage: With backup directory specified by parameter: ./wprestore.sh <BackupName> <BackupDirectory> (e.g. ./wprestore.sh 2021_07_19 /database/test10/)'"
    exit 1
fi

# Check for root
if [ "$(id -u)" != "0" ]
then
    errormessage "ERROR: This script has to be run as root!"
    exit 1
fi

# Check if backup dir exists
if [ ! -d "${currentRestoreDir}" ]
then
    errormessage "ERROR: Backup ${dateRestore} not found!"
    exit 1
fi

# Stop web server
echo "Stopping web server..."
systemctl stop "${webserverServiceName}"
echo "Done!"

# Delete old WP directory
echo "Deleting old Wordpress file directory..."
rm -r "${wordpressFileDir}" &>>'/var/log/cop.log'
mkdir -p "${wordpressFileDir}"
echo "Done!"

# Restore WP file directory
echo "Restoring Wordpress file directory..."
tar -I pigz -xmpf "${currentRestoreDir}/${fileNameBackupFileDir}" -C "${wordpressFileDir}"
echo "Done!"

#Stop MySQL server
echo "Stopping mysql..."
systemctl stop mysql.service
echo "Done!"

#Restoritg mysql db from archive
echo "Restoring Wordpress file directory..."
mkdir -p "${currentRestoreDir}/tmpdb"
tar -I pigz -xmpf "${currentRestoreDir}/${fileNameBackupDb}" -C "${currentRestoreDir}/tmpdb"
echo "Done!"

#Remove old Database
echo "Remove old mysql db..."
rm -rf "${dbDataDir}"
mkdir -p "${dbDataDir}"
echo "Remove is complete"

#Restore Database
echo "Restoring backup DB..."
xtrabackup --user="${dbUser}" --password="${dbPassword}" --copy-back --target-dir="${currentRestoreDir}/tmpdb" &>>'/var/log/cop.log'
EXITCODE=$?
if [ $EXITCODE != 0 ]
then
    errormessage "Error restore backup $EXITCODE"
    exit 1;
fi

echo "Database restore is complete"

#Start mysql and web server
rm -rf "${currentRestoreDir}/tmpdb"
chown -R mysql:mysql "${dbDataDir}"
echo "Starting mysql-server"
systemctl start mysql.service
echo "Done!"

echo "Start web server"
systemctl start "${webserverServiceName}"
echo "Done!"

#Set directory permissions
echo "Setting directory permissions..."
chown -R "${webserverUser}":"${webserverUser}" "${wordpressFileDir}"
echo "Done!"

echo "Backup ${dateRestore} successfully restored."

