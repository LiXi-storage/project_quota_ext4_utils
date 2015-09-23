#!/bin/bash
export DEVICE="/dev/sdb1"
export MNT=/mnt/ext4
export USER=quota_usr
export SAVE_PWD=${SAVE_PWD:-$PWD}
export RUNAS="$SAVE_PWD/runas -u $USER"
export FAIL_ON_ERROR=${FAIL_ON_ERROR:-yes}
export TEST_DIR=$MNT/quota_test
export TEST_DIR1=$MNT/quota_test1
export DD="dd if=/dev/zero bs=1M"
export CREATE_MANY="$SAVE_PWD/createmany"
export GETQUOTA="$SAVE_PWD/parse_quota.py"
export DEFAULT_PROJECT="0"

log () {
	echo $*
}

pass() {
	$TEST_FAILED && echo -n "FAIL " || echo -n "PASS "
	echo $@
}

error_noexit()
{
	log "== ${TESTSUITE} ${TESTNAME} failed: $@ == `date +%H:%M:%S`"
	TEST_FAILED=true
}

error()
{
	error_noexit "$@"
	[ "$FAIL_ON_ERROR" = "yes" ] && exit 1 || true
}

error_exit() {
	error_noexit "$@"
	exit 1
}

cleanup_dir()
{
	local DIR=$1
	if [ "$DIR" = "" ]; then
		error "no directory is given"
	fi

	if [ "$DIR" = "/" ]; then
		error "dangerous direcotry"
	fi

	rm $DIR/* -fr
}

remove_dir()
{
	local DIR=$1
	if [ "$DIR" = "" ]; then
		error "no directory is given"
	fi

	if [ "$DIR" = "/" ]; then
		error "dangerous direcotry"
	fi

	rm $DIR -fr
}

basetest() {
	if [[ $1 = [a-z]* ]]; then
		echo $1
	else
		echo ${1%%[a-z]*}
	fi
}

run_one() {
	testnum=$1
	message=$2
	export tfile=f${testnum}
	export tdir=d${testnum}

	local SAVE_UMASK=`umask`
	umask 0022

	local BEFORE=`date +%s`
	echo
	log "== test $testnum: $message == `date +%H:%M:%S`"

	export TESTNAME=test_$testnum
	TEST_FAILED=false
	test_${testnum} || error "test_$testnum failed with $?"

	cd $SAVE_PWD

	pass "($((`date +%s` - $BEFORE))s)"
	TEST_FAILED=false
	unset TESTNAME
	unset tdir
	umask $SAVE_UMASK
}

run_test() {
	cleanup_dir $TEST_DIR
	remove_dir $TEST_DIR1

	run_one $1 "$2"
	RET=$?

	cleanup_dir $TEST_DIR
	remove_dir $TEST_DIR1

	return $RET
}

quota_init()
{
	MOUNTED=$(mount | grep $MNT | grep $DEVICE)
	if [ "$MOUNTED" != "" ]; then
		umount $MNT > /dev/null 2>&1
		if [ $? -ne 0 ]; then
			echo "Failed to umount $MNT"
			exit 1
		fi
	fi
	
	mkfs.ext4 $DEVICE -F
	if [ $? -ne 0 ]; then
		echo "Failed to mkfs.ext4 $DEVICE"
		exit 1
	fi
	
	#mount $DEVICE -t ldiskfs -o usrquota,grpquota $MNT > /dev/null 2>&1
	mount $DEVICE -t ext4 -o usrquota,grpquota $MNT > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "Failed to mount $DEVICE to $MNT"
		exit 1
	fi
	
	chmod 777 $MNT
	if [ $? -ne 0 ]; then
		echo "Failed to chmod $MNT"
		exit 1
	fi

	MOUNT_OPTION=$(mount | grep $DEVICE | grep $MNT)
	QUOTA_OPTION=$(echo $MOUNT_OPTION | grep usrquota,grpquota)
	if [ "$QUOTA_OPTION" = "" ]; then
		echo "Quota user/group/project on $MNT is not enabled"
		exit 1
	fi

	quotaoff $MNT > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "Failed to turn off quota on $MNT"
		exit 1
	fi
	
	quotacheck -u $MNT > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "Failed to check user quota on $MNT"
		exit 1
	fi
	
	quotacheck -g $MNT > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "Failed to check group quota on $MNT"
		exit 1
	fi
	
	quotaon -ug $MNT
	if [ $? -ne 0 ]; then
		echo "Failed to quotaon user/group/project quota on $MNT"
		exit 1
	fi
	
	mkdir $TEST_DIR
	chmod 777 $TEST_DIR
}

total_blocks() {
	local MOUNT=$1

	df $MOUNT | grep -v Filesystem | awk '{print $2}'
}

used_blocks() {
	local MOUNT=$1

	df $MOUNT | grep -v Filesystem | awk '{print $3}'
}

free_blocks() {
	local MOUNT=$1

	df $MOUNT | grep -v Filesystem | awk '{print $4}'
}

total_inodes() {
	local MOUNT=$1

	df -i $MOUNT | grep -v Filesystem | awk '{print $2}'
}

used_inodes() {
	local MOUNT=$1

	df -i $MOUNT | grep -v Filesystem | awk '{print $3}'
}

free_inodes() {
	local MOUNT=$1

	df -i $MOUNT | grep -v Filesystem | awk '{print $4}'
}

quota_init

test_7() {
	local BLK_CNT=2 # 2 MB

	log "Create..."
	$RUNAS touch $TEST_DIR/$tfile

	$RUNAS $DD of=$TEST_DIR/$tfile count=$BLK_CNT 2>/dev/null ||
	error "write failed"

	local USED=$($GETQUOTA -u $USER $DEVICE curspace)
	[ "$USED" != "2048" ] && error "Used space($USED) for user $USER isn't 2048"
	USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "1" ] && error "Used inodes($USED) isn't 1"

	log "Remount..."
	umount $MNT || \
		error "umount failure, expect success"
	mount $DEVICE -t ext4 -o usrquota,grpquota $MNT || \
		error "mount failure, expect success"
	quotaon $MNT

	USED=$($GETQUOTA -u $USER $DEVICE curspace)
	[ "$USED" != "2048" ] && error "Used space($USED) for user $USER isn't 2048"
	USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "1" ] && error "Used inodes($USED) isn't 1"

	log "Append to the same file..."
	$RUNAS $DD of=$TEST_DIR/$tfile count=$BLK_CNT seek=1 2>/dev/null ||
		error "write failed"
	USED=$($GETQUOTA -u $USER $DEVICE curspace)
	[ "$USED" != "3072" ] && error "Used space($USED) for user $USER isn't 3072."
	USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "1" ] && error "Used inodes($USED) isn't 1"
	return 0
}
run_test 7 "Usage is still accessible across remount"
