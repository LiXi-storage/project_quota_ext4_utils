#!/bin/bash
export DEVICE="/dev/sdb1"
export MNT=/mnt/ext4
export USER=quota_usr
export GROUP=quota_usr
export SAVE_PWD=${SAVE_PWD:-$PWD}
export RUNAS="$SAVE_PWD/runas -u $USER"
export FAIL_ON_ERROR=${FAIL_ON_ERROR:-yes}
export TEST_DIR=$MNT/quota_test
export TEST_DIR1=$MNT/quota_test1
export DD="dd if=/dev/zero bs=1M"
export PROJECT="1776"
export PROJECT1="6771"
export CREATE_MANY="$SAVE_PWD/createmany"
export GETQUOTA="$SAVE_PWD/parse_quota.py"
export SETPROJECT="$SAVE_PWD/project_manage/setproject"
export GETPROJECT="$SAVE_PWD/project_manage/getproject"
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
	chown root $TEST_DIR
	setquota -u $USER 0 0 0 0 $MNT
	setquota -g $GROUP 0 0 0 0 $MNT
	remove_dir $TEST_DIR1

	run_one $1 "$2"
	RET=$?

	cleanup_dir $TEST_DIR
	chown root $TEST_DIR
	setquota -u $USER 0 0 0 0 $MNT
	setquota -g $GROUP 0 0 0 0 $MNT
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
		echo "Quota user/group on $MNT is not enabled"
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
		echo "Failed to quotaon user/group quota on $MNT"
		exit 1
	fi
	
	mkdir $TEST_DIR
	chmod 777 $TEST_DIR
}

getproject() {
	local FILE=$1
	$GETPROJECT --only-values $FILE
}

setproject() {
	local FILE=$1
	local VALUE=$2
	$SETPROJECT -v $VALUE $FILE
	if [ $? -ne 0 ]; then
		error "failed to set project"
	fi

	local GOT_VALUE=$(getproject $FILE)
	if [ "$GOT_VALUE" != "$VALUE" ]; then
		error "failed to set project, expected $VALUE, got $GOT_VALUE"
	fi
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

# test project ID interface
test_0() {
	touch $TEST_DIR/$tfile
	setproject $TEST_DIR/$tfile $PROJECT

	log "Remount..."
	umount $MNT || \
		error "umount failure, expect success"
	mount $DEVICE -t ext4 -o usrquota,grpquota $MNT || \
		error "mount failure, expect success"
	quotaon $MNT

	local VALUE=$(getproject $TEST_DIR/$tfile)
	if [ "$VALUE" != "$PROJECT" ]; then
		error "project changed, expected $PROJECT, got $VALUE"
	fi
	return 0;
}
run_test 0 "Project ID interface"

# test block hardlimit
test_1() {
	local LIMIT=10  # 10M

	local FREE_BLOCKS=$(free_blocks $MNT)
	echo "$FREE_BLOCKS free blocks on $MNT"
	local BLOCK_LIMIT=$(expr $LIMIT \* 1024)
	[ $FREE_BLOCKS -lt $BLOCK_LIMIT ] &&
		error "not enough free blocks $FREE_BLOCKS required $BLOCK_LIMIT"

	# Set quota
	log "user quota (block hardlimit:$LIMIT MB)"
	setquota -u $USER 0 ${LIMIT}M 0 0 $MNT ||
		error "set user quota failed"

	# make sure the system is clean
	local USED=$($GETQUOTA -u $USER $DEVICE curspace)
	[ "$USED" != "0" ] && error "Used space($USED) for user $USER isn't 0."

	log "Create..."
	$RUNAS touch $TEST_DIR/$tfile

	log "Write..."
	$RUNAS $DD of=$TEST_DIR/$tfile count=$((LIMIT/2)) ||
		error "user write failure, but expect success"

	# Check the used value is equal to written size
	USED=$($GETQUOTA -u $USER $DEVICE curspace)
	[ "$USED" != "5120" ] && error "Used space($USED) for user $USER isn't 5120."

	log "Write out of block quota ..."
	# this time maybe cache write,  ignore it's failure
	$RUNAS $DD of=$TEST_DIR/$tfile bs=1048576 count=$((LIMIT/2)) seek=$((LIMIT/2)) || true

	# Check the used value is equal to written size
	USED=$($GETQUOTA -u $USER $DEVICE curspace)
	[ "$USED" != "10240" ] && error "Used space($USED) for user $USER isn't 10240."

	$RUNAS $DD bs=1048576 of=$TEST_DIR/$tfile bs=1048576 count=1 seek=$LIMIT &&
		error "user write success, but expect EDQUOT"

	# Check the used value is equal to quota limit
	USED=$($GETQUOTA -u $USER $DEVICE curspace)
	[ "$USED" != "10240" ] && error "Used space($USED) for user $USER isn't 10240."

	rm -f $TEST_DIR/$tfile
	USED=$($GETQUOTA -u $USER $DEVICE curspace)
	[ "$USED" != "0" ] && error "user quota isn't released after deletion"

	return 0
}
run_test 1 "Block hard limit (normal use and out of quota)"

# test inode hardlimit
test_2() {
	local LIMIT=1024 # 1k inodes

	local FREE_INODES=$(free_inodes $MNT)
	echo "$FREE_INODES free inodes on $MNT"
	[ $FREE_INODES -lt $LIMIT ] &&
		error "not enough free inodes $FREE_INODES required $LIMIT"

	# Set quota
	log "Porject quota (inode hardlimit:$LIMIT files)"
	setquota -u $USER 0 0 0 $LIMIT $MNT ||
		error "set user quota failed"

	# make sure the system is clean
	local USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "0" ] && error "Used inode($USED) for user $USER isn't 0."

	# Prepare direcotry
	chown $USER $TEST_DIR
	local USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "1" ] && error "Used inode($USED) for user $USER isn't 1."

	$RUNAS $CREATE_MANY -m $TEST_DIR/$tfile-0 $((LIMIT-1))|| \
		error "user create failure, but expect success"
	local USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "$LIMIT" ] && error "Used inode($USED) for user $USER isn't $LIMIT."

	$RUNAS touch $TEST_DIR/$tfile && \
		error "user create success, but expect EDQUOT"
	local USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "$LIMIT" ] && error "Used inode($USED) for user $USER isn't $LIMIT."

	rm $TEST_DIR/* -f
	rm -f $TEST_DIR/$tfile -f
	local USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "1" ] && error "Used inode($USED) isn't released after deletion"

	chown root $TEST_DIR
	local USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "0" ] && error "Used inode($USED) isn't released after change owner"

	return 0
}
run_test 2 "File hard limit (normal use and out of quota)"

# Block soft limit
test_3() {
	local LIMIT=1  # 1MB
	local GRACE=20 # 20s
	local TIMER=$(($GRACE * 3 / 2))

	local FREE_BLOCKS=$(free_blocks $MNT)
	echo "$FREE_BLOCKS free blocks on $MNT"
	local BLOCK_LIMIT=$(expr $LIMIT \* 1024)
	[ $FREE_BLOCKS -lt $BLOCK_LIMIT ] &&
		error "not enough free blocks $FREE_BLOCKS required $BLOCK_LIMIT"

	# make sure the system is clean
	local USED=$($GETQUOTA -u $USER $DEVICE curspace)
	[ "$USED" != "0" ] && error "Used space($USED) for user $USER isn't 0."

	setquota -t -u $GRACE 604800 $MNT

	setquota -u $USER ${LIMIT}M 0 0 0 $MNT || \
		error "set user quota failed"

	log "Create..."
	$RUNAS touch $TEST_DIR/$tfile

	echo "Write up to soft limit"
	$RUNAS $DD of=$TEST_DIR/$tfile count=$LIMIT || \
		error "write failure, but expect success"
	local OFFSET=$((LIMIT * 1024))

	echo "Write to exceed soft limit"
	$RUNAS dd if=/dev/zero of=$TEST_DIR/$tfile bs=1K count=10 seek=$OFFSET || \
		error "write failure, but expect success"
	OFFSET=$((OFFSET + 1024)) # make sure we don't write to same block

	echo "Write before timer goes off"
	$RUNAS dd if=/dev/zero of=$TEST_DIR/$tfile bs=1K count=10 seek=$OFFSET || \
		error "write failure, but expect success"
	OFFSET=$((OFFSET + 1024))

	echo "Sleep $TIMER seconds ..."
	sleep $TIMER

	# Make sure timer goes off
	local GRACE=$($GETQUOTA -u $USER $DEVICE bgrace)
	[ "$GRACE" != "none" ] && error "Grace($GRACE) for user $USER isn't none."

	echo "Write after timer goes off"
	$RUNAS dd if=/dev/zero of=$TEST_DIR/$tfile bs=1K count=10 seek=$OFFSET &&
		error "user write success, but expect EDQUOT"
	OFFSET=$((OFFSET + 1024))

	echo "Unlink file to stop timer"
	rm -f $TEST_DIR/$tfile

	log "Create..."
	$RUNAS touch $TEST_DIR/$tfile

	echo "Write ..."
	$RUNAS $DD of=$TEST_DIR/$tfile count=$LIMIT ||
		error "write failure, but expect success"
	return 0
}
run_test 3 "Block soft limit (start timer, timer goes off, stop timer)"


# Inode soft limit
test_4() {
	local LIMIT=10 # inodes
	local GRACE=20 # 20s
	local TIMER=$(($GRACE * 3 / 2))

	# make sure the system is clean
	local USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "0" ] && error "Used inodes($USED) for user $USER isn't 0."

	setquota -t -u 604800 $GRACE $MNT

	setquota -u $USER 0 0 $LIMIT 0 $MNT || \
		error "set user quota failed"

	# Prepare direcotry
	chown $USER $TEST_DIR
	local USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "1" ] && error "Used inode($USED) for user $USER isn't 1."

	$RUNAS $CREATE_MANY -m $TEST_DIR/$tfile-0 $((LIMIT-1))|| \
		error "user create failure, but expect success"
	local USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "$LIMIT" ] && error "Used inode($USED) for user $USER isn't $LIMIT."

	echo "Create file before timer goes off"
	$RUNAS touch $TEST_DIR/${tfile}_before || \
		error "user create failure, but expect success"
	local USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "$((LIMIT+1))" ] && error "Used inode($USED) for user $USER isn't $((LIMIT+1))."

	echo "Sleep $TIMER seconds ..."
	sleep $TIMER

	# Make sure timer goes off
	local GRACE=$($GETQUOTA -u $USER $DEVICE igrace)
	[ "$GRACE" != "none" ] && error "Grace($GRACE) for user $USER isn't none."

	echo "Create file after timer goes off"
	$RUNAS touch $TEST_DIR/${tfile}_after && \
		error "user create success, but expect EDQUOT"
	local USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "$((LIMIT+1))" ] && error "Used inode($USED) for user $USER isn't $((LIMIT+1))."

	echo "Unlink file to stop timer"
	rm -f $TEST_DIR/*

	log "Create..."
	$RUNAS touch $TEST_DIR/$tfile ||
		error "create failure, but expect success"
	return 0
}
run_test 4 "Inode soft limit (start timer, timer goes off, stop timer)"

# Change user (change user successfully even out of block/file quota)
test_5() {
	local BLIMIT=10 # 10M
	local ILIMIT=10 # 10 inodes

	local FREE_BLOCKS=$(free_blocks $MNT)
	echo "$FREE_BLOCKS free blocks on $MNT"
	local BLOCK_LIMIT=$(expr $BLIMIT \* 1024)
	[ $FREE_BLOCKS -lt $BLOCK_LIMIT ] &&
		error "not enough free blocks $FREE_BLOCKS required $BLOCK_LIMIT"
	
	local FREE_INODES=$(free_inodes $MNT)
	echo "$FREE_INODES free inodes on $MNT"
	[ $FREE_INODES -lt $ILIMIT ] &&
		error "not enough free inodes $FREE_INODES required $ILIMIT"

	# Set quota
	log "Porject quota (block hardlimit:$LIMIT MB)"
	setquota -u $USER 0 ${BLIMIT}M 0 $ILIMIT $MNT || \
		error "set user quota failed"

	# make sure the system is clean
	local USED=$($GETQUOTA -u $USER $DEVICE curspace)
	[ "$USED" != "0" ] && error "Used space($USED) for user $USER isn't 0."
	USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "0" ] && error "Used inode($USED) for user $USER isn't 0."

	# Prepare direcotry
	chown $USER $TEST_DIR
	USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "1" ] && error "Used inode($USED) for user $USER isn't 1."

	log "Create more than $ILIMIT using root"
	$CREATE_MANY -m $TEST_DIR/$tfile-0 $ILIMIT || \
		error "user create failure, but expect success"
	local ITER;
	for ((ITER = 0; ITER < $ILIMIT; ITER++)) {
		chown $USER $TEST_DIR/$tfile-0${ITER}|| \
			error "user chown failure, but expect success"
	}
	USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "$((ILIMIT+1))" ] && error "Used inode($USED) for user $USER isn't $((ILIMIT+1))."

	log "Create more than $ILIMIT using normal user"
	$RUNAS touch $TEST_DIR/$tfile && \
		error "user create success, but expect EDQUOT"

	log "Set user of directory to 0"
	chown root $TEST_DIR || \
			error "change owner failure, expect success"
	USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "$ILIMIT" ] && error "Used inode($USED) for user $USER isn't $ILIMIT."
	USED=$($GETQUOTA -u $USER $DEVICE curspace)
	[ "$USED" != "0" ] && error "Used space($USED) for user $USER isn't 0."

	log "Create more than $ILIMIT again"
	touch $TEST_DIR/$tfile
	chown $USER $TEST_DIR/$tfile
	USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "$((ILIMIT+1))" ] && error "Used inode($USED) for user $USER isn't $((ILIMIT+1))."
	USED=$($GETQUOTA -u $USER $DEVICE curspace)
	[ "$USED" != "0" ] && error "Used space($USED) for user $USER isn't 0."

	log "Write up to $BLIMIT MB ..."
	$DD of=$TEST_DIR/$tfile count=$((BLIMIT+1)) || \
		error "Write failure, expect success"
	USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "$((ILIMIT+1))" ] && error "Used inode($USED) for user $USER isn't $((ILIMIT+1))."
	USED=$($GETQUOTA -u $USER $DEVICE curspace)
	[ "$USED" != "11264" ] && error "Used space($USED) for user $USER isn't $((BLIMIT+1))."

	log "Write more than $BLIMIT MB using normal user"
	chmod 777 $TEST_DIR/$tfile-00
	$RUNAS $DD of=$TEST_DIR/$tfile-00 count=1 && \
		error "user write success, but expect EDQUOT"

	USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "$((ILIMIT+1))" ] && error "Used inode($USED) for user $USER isn't $((ILIMIT+1))."
	USED=$($GETQUOTA -u $USER $DEVICE curspace)
	[ "$USED" != "11264" ] && error "Used space($USED) for user $USER isn't $((BLIMIT+1))."

	log "Chang user to 0 ..."
	for i in `seq 0 $((ILIMIT-1))`; do
		chown root $TEST_DIR/$tfile-0$i || \
			error "change owner failure, expect success"
	done
	chown root $TEST_DIR/$tfile || \
			error "change owner failure, expect success"

	USED=$($GETQUOTA -u $USER $DEVICE curspace)
	[ "$USED" != "0" ] && error "Used space($USED) for user $USER isn't 0."
	USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "0" ] && error "Used inode($USED) for user $USER isn't 0."

	return 0
}
run_test 5 "user successfully even out of block/file quota"


test_6() {
	setquota -u $USER 0 0 0 1 $MNT || \
		error "set quota failed"

	touch $TEST_DIR/$tfile-0
	touch $TEST_DIR/$tfile-1
	chown $USER $TEST_DIR/$tfile-0 || \
			error "change owner failure, expect success"
	chown $USER $TEST_DIR/$tfile-1 || \
			error "change owner failure, expect success"

	local USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "2" ] && error "Used inodes($USED) isn't 2"

	return 0
}
run_test 6 "Change owner ignores quota"

test_7() {
	local BLK_CNT=2 # 2 MB

	log "Create..."
	$RUNAS touch $TEST_DIR/$tfile
	chown $USER $TEST_DIR/$tfile

	$RUNAS $DD of=$TEST_DIR/$tfile count=$BLK_CNT 2>/dev/null ||
	error "write failed"

	local USED=$($GETQUOTA -u $USER $DEVICE curspace)
	[ "$USED" != "2048" ] && error "Used space($USED) for user $USER isn't 2048"
	USED=$($GETQUOTA -u $USER $DEVICE curinodes)
	[ "$USED" != "1" ] && error "Used inodes($USED) isn't 1"

	log "Remount..."
	umount $MNT || \
		error "umount failure, expect success"
	mount $DEVICE -t ext4 -o usrquota,grpquota,prjquota $MNT || \
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
