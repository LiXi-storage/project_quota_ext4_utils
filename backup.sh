#!/bin/bash
SOURCES="e2fsprogs.git linux-git quota-tools.git"
BACKUP="backup"
TIME=$(date +%s)
DIR="$BACKUP/project_quota_support_for_ext4_$TIME"

backup_patch()
{
	local SOURCE_DIR="$1"
	local BACKUP_DIR="$DIR/$SOURCE_DIR"
	local SERIES=$(cat $SOURCE_DIR/patches/series)
	FOMER_PWD=$(pwd)
	cd $SOURCE_DIR
	quilt refresh
	cd $FOMER_PWD
	mkdir -p $BACKUP_DIR
	mkdir $BACKUP_DIR/patches
	cp $cp $SOURCE_DIR/patches/series $BACKUP_DIR/series
	for PATCH in $SERIES; do
		cp $SOURCE_DIR/patches/$PATCH $BACKUP_DIR/patches
	done
}

mkdir $DIR
for SOURCE in $SOURCES; do
	backup_patch $SOURCE
done
cp *.sh $DIR
cp *.py $DIR
cd project_manage
make clean
cd ..
cp project_manage -a $DIR
