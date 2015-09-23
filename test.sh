#!/bin/bash
export DEVICE="/dev/sda3"
export MNT=/mnt/ext4
export USER=quota_usr
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

	rm $DIR/* -rf
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

set_inherit() {
	local FILE=$1
	chattr +P $FILE
	if [ $? -ne 0 ]; then
		error "failed to chattr"
	fi

	if [ -d $FILE ]; then
		local DIR_ARG="-d"
	fi

	local ATTR=$(lsattr $FILE $DIR_ARG | grep P)
	if [ "$ATTR" = "" ]; then
		error "failed to lsattr"
	fi
}

clear_inherit() {
	local FILE=$1
	chattr -P $FILE
	if [ $? -ne 0 ]; then
		error "failed to chattr"
	fi

	if [ -d $FILE ]; then
		local DIR_ARG="-d"
	fi

	local ATTR=$(lsattr $FILE $DIR_ARG | grep P)
	if [ "$ATTR" != "" ]; then
		error "failed to lsattr"
	fi
}

get_inherit() {
	local FILE=$1

	if [ -d $FILE ]; then
		local DIR_ARG="-d"
	fi

	local ATTR=$(lsattr $FILE $DIR_ARG | grep P)
	if [ "$ATTR" != "" ]; then
		echo 'true'
		return 0
	fi
	echo 'false'
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
	if [ "$PROJECT_ENABLED" = "yes" ]; then
		setproject $TEST_DIR $DEFAULT_PROJECT
	fi
	clear_inherit $TEST_DIR
	if [ "$PROJECT_ENABLED" = "yes" ]; then
		setquota -P $PROJECT 0 0 0 0 $MNT
	fi
	remove_dir $TEST_DIR1

	run_one $1 "$2"
	RET=$?

	cleanup_dir $TEST_DIR
	if [ "$PROJECT_ENABLED" = "yes" ]; then
		setproject $TEST_DIR $DEFAULT_PROJECT
	fi
	clear_inherit $TEST_DIR
	if [ "$PROJECT_ENABLED" = "yes" ]; then
		setquota -P $PROJECT 0 0 0 0 $MNT
	fi
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
	
	mkfs.ext4 -O project,quota $DEVICE -F
	if [ $? -ne 0 ]; then
		echo "Failed to mkfs.ext4 $DEVICE"
		exit 1
	fi
	
	mount $DEVICE -t ext4 $MNT > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "Failed to mount $DEVICE to $MNT"
		exit 1
	fi
	
	chmod 777 $MNT
	if [ $? -ne 0 ]; then
		echo "Failed to chmod $MNT"
		exit 1
	fi

	mkdir $TEST_DIR
	chmod 777 $TEST_DIR
	export PROJECT_ENABLED='yes'
}

getproject() {
	local FILE=$1
	$GETPROJECT --only-values $FILE
}

setproject() {
	local FILE=$1
	local VALUE=$2
	echo "XXX $SETPROJECT -v $VALUE $FILE"
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
	mount $DEVICE -t ext4 $MNT || \
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
	log "Porject quota (block hardlimit:$LIMIT MB)"
	echo "setquota -P $PROJECT 0 ${LIMIT}M 0 0 $MNT"
	setquota -P $PROJECT 0 ${LIMIT}M 0 0 $MNT ||
		error "set project quota failed"

	# make sure the system is clean
	local USED=$($GETQUOTA -P $PROJECT $DEVICE curspace)
	[ "$USED" != "0" ] && error "Used space($USED) for project $PROJECT isn't 0."

	log "Create..."
	$RUNAS touch $TEST_DIR/$tfile
	setproject $TEST_DIR/$tfile $PROJECT

	log "Write..."
	$RUNAS $DD of=$TEST_DIR/$tfile count=$((LIMIT/2)) ||
		error "user write failure, but expect success"

	# Check the used value is equal to written size
	USED=$($GETQUOTA -P $PROJECT $DEVICE curspace)
	[ "$USED" != "5120" ] && error "Used space($USED) for project $PROJECT isn't 5120."

	log "Write out of block quota ..."
	# this time maybe cache write,  ignore it's failure
	$RUNAS $DD of=$TEST_DIR/$tfile bs=1048576 count=$((LIMIT/2)) seek=$((LIMIT/2)) || true

	# Check the used value is equal to written size
	USED=$($GETQUOTA -P $PROJECT $DEVICE curspace)
	[ "$USED" != "10240" ] && error "Used space($USED) for project $PROJECT isn't 10240."

	$RUNAS $DD bs=1048576 of=$TEST_DIR/$tfile bs=1048576 count=1 seek=$LIMIT &&
		error "user write success, but expect EDQUOT"

	# Check the used value is equal to quota limit
	USED=$($GETQUOTA -P $PROJECT $DEVICE curspace)
	[ "$USED" != "10240" ] && error "Used space($USED) for project $PROJECT isn't 10240."

	rm -f $TEST_DIR/$tfile
	USED=$($GETQUOTA -P $PROJECT $DEVICE curspace)
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
	setquota -P $PROJECT 0 0 0 $LIMIT $MNT ||
		error "set project quota failed"

	# make sure the system is clean
	local USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "0" ] && error "Used inode($USED) for project $PROJECT isn't 0."

	# Prepare direcotry
	setproject $TEST_DIR $PROJECT
	local USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "1" ] && error "Used inode($USED) for project $PROJECT isn't 1."
	set_inherit $TEST_DIR || error "set inherit failed"

	$RUNAS $CREATE_MANY -m $TEST_DIR/$tfile-0 $((LIMIT-1))|| \
		error "project create failure, but expect success"
	local USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "$LIMIT" ] && error "Used inode($USED) for project $PROJECT isn't $LIMIT."

	$RUNAS touch $TEST_DIR/$tfile && \
		error "project create success, but expect EDQUOT"
	local USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "$LIMIT" ] && error "Used inode($USED) for project $PROJECT isn't $LIMIT."

	rm $TEST_DIR/* -f
	rm $TEST_DIR/$tfile -f
	local USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "1" ] && error "Used inode($USED) isn't released after deletion"

	setproject $TEST_DIR $DEFAULT_PROJECT
	local USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "0" ] && error "Used inode($USED) isn't released after change project"

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
	local USED=$($GETQUOTA -P $PROJECT $DEVICE curspace)
	[ "$USED" != "0" ] && error "Used space($USED) for project $PROJECT isn't 0."

	setquota -t -P $GRACE 604800 $MNT

	setquota -P $PROJECT ${LIMIT}M 0 0 0 $MNT || \
		error "set project quota failed"

	log "Create..."
	$RUNAS touch $TEST_DIR/$tfile
	setproject $TEST_DIR/$tfile $PROJECT

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
	local GRACE=$($GETQUOTA -P $PROJECT $DEVICE bgrace)
	[ "$GRACE" != "none" ] && error "Grace($GRACE) for project $PROJECT isn't none."

	echo "Write after timer goes off"
	$RUNAS dd if=/dev/zero of=$TEST_DIR/$tfile bs=1K count=10 seek=$OFFSET &&
		error "user write success, but expect EDQUOT"
	OFFSET=$((OFFSET + 1024))

	echo "Unlink file to stop timer"
	rm -f $TEST_DIR/$tfile

	log "Create..."
	$RUNAS touch $TEST_DIR/$tfile
	setproject $TEST_DIR/$tfile $PROJECT

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
	local USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "0" ] && error "Used inodes($USED) for project $PROJECT isn't 0."

	setquota -t -P 604800 $GRACE $MNT

	setquota -P $PROJECT 0 0 $LIMIT 0 $MNT || \
		error "set project quota failed"

	# Prepare direcotry
	setproject $TEST_DIR $PROJECT
	local USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "1" ] && error "Used inode($USED) for project $PROJECT isn't 1."
	set_inherit $TEST_DIR || error "set inherit failed"

	$RUNAS $CREATE_MANY -m $TEST_DIR/$tfile-0 $((LIMIT-1))|| \
		error "project create failure, but expect success"
	local USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "$LIMIT" ] && error "Used inode($USED) for project $PROJECT isn't $LIMIT."

	echo "Create file before timer goes off"
	$RUNAS touch $TEST_DIR/${tfile}_before || \
		error "project create failure, but expect success"
	local USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "$((LIMIT+1))" ] && error "Used inode($USED) for project $PROJECT isn't $((LIMIT+1))."

	echo "Sleep $TIMER seconds ..."
	sleep $TIMER

	# Make sure timer goes off
	local GRACE=$($GETQUOTA -P $PROJECT $DEVICE igrace)
	[ "$GRACE" != "none" ] && error "Grace($GRACE) for project $PROJECT isn't none."

	echo "Create file after timer goes off"
	$RUNAS touch $TEST_DIR/${tfile}_after && \
		error "project create success, but expect EDQUOT"
	local USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "$((LIMIT+1))" ] && error "Used inode($USED) for project $PROJECT isn't $((LIMIT+1))."

	echo "Unlink file to stop timer"
	rm -f $TEST_DIR/*

	log "Create..."
	$RUNAS touch $TEST_DIR/$tfile ||
		error "create failure, but expect success"
	return 0
}
run_test 4 "Inode soft limit (start timer, timer goes off, stop timer)"

# Change project (change project successfully even out of block/file quota)
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
	setquota -P $PROJECT 0 ${BLIMIT}M 0 $ILIMIT $MNT || \
		error "set project quota failed"

	# make sure the system is clean
	local USED=$($GETQUOTA -P $PROJECT $DEVICE curspace)
	[ "$USED" != "0" ] && error "Used space($USED) for project $PROJECT isn't 0."
	USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "0" ] && error "Used inode($USED) for project $PROJECT isn't 0."

	# Prepare direcotry
	setproject $TEST_DIR $PROJECT
	USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "1" ] && error "Used inode($USED) for project $PROJECT isn't 1."
	set_inherit $TEST_DIR || error "set inherit failed"

	log "Create more than $ILIMIT using root"
	$CREATE_MANY -m $TEST_DIR/$tfile-0 $ILIMIT || \
		error "project create failure, but expect success"
	USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "$((ILIMIT+1))" ] && error "Used inode($USED) for project $PROJECT isn't $((ILIMIT+1))."

	log "Create more than $ILIMIT using normal user"
	$RUNAS touch $TEST_DIR/$tfile && \
		error "project create success, but expect EDQUOT"

	log "Set project of directory to $DEFAULT_PROJECT"
	setproject $TEST_DIR $DEFAULT_PROJECT || \
			error "change project failure, expect success"
	USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "$ILIMIT" ] && error "Used inode($USED) for project $PROJECT isn't $ILIMIT."
	USED=$($GETQUOTA -P $PROJECT $DEVICE curspace)
	[ "$USED" != "0" ] && error "Used space($USED) for project $PROJECT isn't 0."

	log "Create more than $ILIMIT again"
	touch $TEST_DIR/$tfile
	setproject $TEST_DIR/$tfile $PROJECT
	USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "$((ILIMIT+1))" ] && error "Used inode($USED) for project $PROJECT isn't $((ILIMIT+1))."
	USED=$($GETQUOTA -P $PROJECT $DEVICE curspace)
	[ "$USED" != "0" ] && error "Used space($USED) for project $PROJECT isn't 0."

	log "Write up to $BLIMIT MB ..."
	$DD of=$TEST_DIR/$tfile count=$((BLIMIT+1)) || \
		error "Write failure, expect success"
	USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "$((ILIMIT+1))" ] && error "Used inode($USED) for project $PROJECT isn't $((ILIMIT+1))."
	USED=$($GETQUOTA -P $PROJECT $DEVICE curspace)
	[ "$USED" != "11264" ] && error "Used space($USED) for project $PROJECT isn't $((BLIMIT+1))."

	log "Write more than $BLIMIT MB using normal user"
	chmod 777 $TEST_DIR/$tfile-00
	$RUNAS $DD of=$TEST_DIR/$tfile-00 count=1 && \
		error "project write success, but expect EDQUOT"

	USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "$((ILIMIT+1))" ] && error "Used inode($USED) for project $PROJECT isn't $((ILIMIT+1))."
	USED=$($GETQUOTA -P $PROJECT $DEVICE curspace)
	[ "$USED" != "11264" ] && error "Used space($USED) for project $PROJECT isn't $((BLIMIT+1))."

	log "Chang project to $DEFAULT_PROJECT ..."
	for i in `seq 0 $((ILIMIT-1))`; do
		setproject $TEST_DIR/$tfile-0$i $DEFAULT_PROJECT || \
			error "change project failure, expect success"
	done
	setproject $TEST_DIR/$tfile $DEFAULT_PROJECT || \
			error "change project failure, expect success"

	USED=$($GETQUOTA -P $PROJECT $DEVICE curspace)
	[ "$USED" != "0" ] && error "Used space($USED) for project $PROJECT isn't 0."
	USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "0" ] && error "Used inode($USED) for project $PROJECT isn't 0."

	return 0
}
run_test 5 "Project successfully even out of block/file quota"


test_6() {
	setquota -P $PROJECT 0 0 0 1 $MNT || \
		error "set quota failed"

	touch $TEST_DIR/$tfile-0
	touch $TEST_DIR/$tfile-1
	setproject $TEST_DIR/$tfile-0 $PROJECT || \
			error "change project failure, expect success"
	setproject $TEST_DIR/$tfile-1 $PROJECT || \
			error "change project failure, expect success"

	local USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "2" ] && error "Used inodes($USED) isn't 2"

	return 0
}
run_test 6 "Change project ignores quota"

test_7() {
	local BLK_CNT=2 # 2 MB

	log "Create..."
	$RUNAS touch $TEST_DIR/$tfile
	setproject $TEST_DIR/$tfile $PROJECT

	$RUNAS $DD of=$TEST_DIR/$tfile count=$BLK_CNT 2>/dev/null ||
	error "write failed"

	local USED=$($GETQUOTA -P $PROJECT $DEVICE curspace)
	[ "$USED" != "2048" ] && error "Used space($USED) for project $PROJECT isn't 2048"
	USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "1" ] && error "Used inodes($USED) isn't 1"

	log "Remount..."
	umount $MNT || \
		error "umount failure, expect success"
	mount $DEVICE -t ext4 $MNT || \
		error "mount failure, expect success"
	quotaon $MNT

	USED=$($GETQUOTA -P $PROJECT $DEVICE curspace)
	[ "$USED" != "2048" ] && error "Used space($USED) for project $PROJECT isn't 2048"
	USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "1" ] && error "Used inodes($USED) isn't 1"

	log "Append to the same file..."
	$RUNAS $DD of=$TEST_DIR/$tfile count=$BLK_CNT seek=1 2>/dev/null ||
		error "write failed"
	USED=$($GETQUOTA -P $PROJECT $DEVICE curspace)
	[ "$USED" != "3072" ] && error "Used space($USED) for project $PROJECT isn't 3072."
	USED=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	[ "$USED" != "1" ] && error "Used inodes($USED) isn't 1"
	return 0
}
run_test 7 "Usage is still accessible across remount"

test_8() {
	setproject $TEST_DIR $PROJECT
	set_inherit $TEST_DIR
	touch $TEST_DIR/$tfile
	local VALUE=$(getproject $TEST_DIR/$tfile)
	if [ "$VALUE" != "$PROJECT" ]; then
		error "project is not inherited, expected $PROJECT, got $VALUE"
	fi
	return 0
}
run_test 8 "Inherit project from parent"

inode_number() {
	local FILE=$1
	ls -i $FILE | awk '{print $1}'
}

test_9() {
	setproject $TEST_DIR $PROJECT
	set_inherit $TEST_DIR
	mkdir $TEST_DIR1
	touch $TEST_DIR1/$tfile
	local INODE_BERFOR_RENAME=$(inode_number $TEST_DIR1/$tfile)
	setproject $TEST_DIR1/$tfile $PROJECT1
	mv $TEST_DIR1/$tfile $TEST_DIR || error "Rename failure, expect success"
	local INODE_AFTER_RENAME=$(inode_number $TEST_DIR/$tfile)
	local VALUE=$(getproject $TEST_DIR/$tfile)
	if [ "$VALUE" != "$PROJECT" ]; then
		error "project is not updated, expected $PROJECT, got $VALUE"
	fi
	if [ "$INODE_BERFOR_RENAME" = "$INODE_AFTER_RENAME" ]; then
		error "Inode number(I$NODE_BERFOR_RENAME) should be different"
	fi
	return 0
}
run_test 9 "Move accross projects works by copying and removing"

test_10() {
	setproject $TEST_DIR $PROJECT
	set_inherit $TEST_DIR
	mkdir $TEST_DIR1
	touch $TEST_DIR1/$tfile
	setproject $TEST_DIR1/$tfile $PROJECT1
	ln $TEST_DIR1/$tfile $TEST_DIR/$tfile && error "Link success, expect failure"
	return 0
}
run_test 10 "Link accross projects should fail"

test_11() {
	setproject $TEST_DIR $PROJECT
	clear_inherit $TEST_DIR
	touch $TEST_DIR/$tfile
	local VALUE=$(getproject $TEST_DIR/$tfile)
	if [ "$VALUE" != "$DEFAULT_PROJECT" ]; then
		error "project is not default, expected 0, got $VALUE"
	fi
	VALUE=$(get_inherit $TEST_DIR/$tfile)
	if [ "$VALUE" != "false" ]; then
		error "Inherit enabled, expected false, got $VALUE"
	fi
	return 0
}
run_test 11 "Default project when not inherit"

test_12() {
	local BLIMIT=10 # 10M
	local BLOCK_LIMIT=$(expr $BLIMIT \* 1024)
	local ILIMIT=1024 # 1024 inodes
	local BLIMIT_SOFT=5 # 10M
	local BLOCK_LIMIT_SOFT=$(expr $BLIMIT_SOFT \* 1024)
	local ILIMIT_SOFT=512 # 512 inodes

	local TOTAL_BLOCKS=$(total_blocks $MNT)
	local TOTAL_INODES=$(total_inodes $MNT)
	local FREE_BLOCKS=$(free_blocks $MNT)
	local FREE_INODES=$(free_inodes $MNT)
	local USED_BLOCKS=$(used_blocks $MNT)
	local USED_INODES=$(used_inodes $MNT)

	[ $TOTAL_BLOCKS -lt $BLOCK_LIMIT ] &&
		error "not enough total blocks $TOTAL_BLOCKS required $BLOCK_LIMIT"

	[ $TOTAL_INODES -lt $ILIMIT ] &&
		error "not enough free inodes $TOTAL_INODES required $ILIMIT"

	# Following is not true even for normal ext4
	#local SUM=$(expr $FREE_BLOCKS + $USED_BLOCKS )
	#[ $SUM -ne $TOTAL_BLOCKS ] &&
	#	error "Sum of free blocks($FREE_BLOCKS) and used blocks($USED_BLOCKS) is not equal to total blocks($TOTAL_BLOCKS)"

	local SUM=$(expr $FREE_INODES + $USED_INODES )
	[ $SUM -ne $TOTAL_INODES ] &&
		error "Sum of free inodes($FREE_INODES) and used inodes($USED_INODES) is not equal to total inodes($TOTAL_INODES)"

	# Set quota limit
	log "Porject quota (block hardlimit:$BLIMIT MB, inode hardlimit:$ILIMIT)"
	setquota -P $PROJECT 0 ${BLIMIT}M 0 ${ILIMIT} $MNT ||
		error "set project quota failed"

	setproject $TEST_DIR $PROJECT

	local TOTAL_BLOCKS_PROJECT=$(total_blocks $TEST_DIR)
	local TOTAL_INODES_PROJECT=$(total_inodes $TEST_DIR)
	local FREE_BLOCKS_PROJECT=$(free_blocks $TEST_DIR)
	local FREE_INODES_PROJECT=$(free_inodes $TEST_DIR)
	local USED_BLOCKS_PROJECT=$(used_blocks $TEST_DIR)
	local USED_INODES_PROJECT=$(used_inodes $TEST_DIR)

	[ "$TOTAL_BLOCKS" != "$TOTAL_BLOCKS_PROJECT" ] &&
		error "block error without inherit, expected $TOTAL_BLOCKS, got $TOTAL_BLOCKS_PROJECT"
	
	[ "$TOTAL_INODES" != "$TOTAL_INODES_PROJECT" ] &&
		error "inode error without inherit, expected $TOTAL_INODES, got $TOTAL_INODES_PROJECT"

	[ "$FREE_BLOCKS" != "$FREE_BLOCKS_PROJECT" ] &&
		error "free block error without inherit, expected $FREE_BLOCKS, got $FREE_BLOCKS_PROJECT"

	[ "$FREE_INODES" != "$FREE_INODES_PROJECT" ] &&
		error "free inode error without inherit, expected $FREE_INODES, got $FREE_INODES_PROJECT"
	
	[ "$USED_BLOCKS" != "$USED_BLOCKS_PROJECT" ] &&
		error "inode error without inherit, expected $USED_BLOCKS, got $USED_BLOCKS_PROJECT"

	[ "$USED_INODES" != "$USED_INODES_PROJECT" ] &&
		error "inode error without inherit, expected $USED_INODES, got $USED_INODES_PROJECT"

	set_inherit $TEST_DIR
	local TOTAL_BLOCKS_PROJECT=$(total_blocks $TEST_DIR)
	local TOTAL_INODES_PROJECT=$(total_inodes $TEST_DIR)
	local FREE_BLOCKS_PROJECT=$(free_blocks $TEST_DIR)
	local FREE_INODES_PROJECT=$(free_inodes $TEST_DIR)
	local USED_BLOCKS_PROJECT=$(used_blocks $TEST_DIR)
	local USED_INODES_PROJECT=$(used_inodes $TEST_DIR)
	local USED_INODES_QUOTA=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	local USED_BLOCKS_QUOTA=$($GETQUOTA -P $PROJECT $DEVICE curspace)

	[ "$BLOCK_LIMIT" != "$TOTAL_BLOCKS_PROJECT" ] &&
		error "block error with inherit, expected $BLOCK_LIMIT, got $TOTAL_BLOCKS_PROJECT"
	
	[ "$ILIMIT" != "$TOTAL_INODES_PROJECT" ] &&
		error "inode error with inherit, expected $ILIMIT, got $TOTAL_INODES_PROJECT"

	[ "$USED_BLOCKS_PROJECT" != "$USED_BLOCKS_QUOTA" ] &&
		error "used block error with inherit, expected $USED_BLOCKS_QUOTA, got $USED_BLOCKS_PROJECT"
	
	[ "$USED_INODES_PROJECT" != "$USED_INODES_QUOTA" ] &&
		error "used inode error with inherit, expected $USED_INODES_QUOTA, got $USED_INODES_PROJECT"

	local SUM=$(expr $FREE_INODES_PROJECT + $USED_INODES_PROJECT )
	[ $SUM -ne $TOTAL_INODES_PROJECT ] &&
		error "Sum of free inodes($FREE_INODES_PROJECT) and used inodes($USED_INODES_PROJECT) is not equal to total inodes($TOTAL_INODES_PROJECT)"

	local SUM=$(expr $FREE_BLOCKS_PROJECT + $USED_BLOCKS_PROJECT )
	[ $SUM -ne $TOTAL_BLOCKS_PROJECT ] &&
		error "Sum of free blocks($FREE_BLOCKS_PROJECT) and used blocks($USED_BLOCKS_PROJECT) is not equal to total blocks($TOTAL_BLOCKS_PROJECT)"

	# Set quota soft limit
	log "Porject quota (block hard/soft:$BLIMIT/$BLIMIT_SOFT MB, inode hard/soft:$ILIMIT/$ILIMIT_SOFT)"
	setquota -P $PROJECT ${BLIMIT_SOFT}M ${BLIMIT}M ${ILIMIT_SOFT} ${ILIMIT} $MNT ||
		error "set project quota failed"

	local TOTAL_BLOCKS_PROJECT=$(total_blocks $TEST_DIR)
	local TOTAL_INODES_PROJECT=$(total_inodes $TEST_DIR)
	local FREE_BLOCKS_PROJECT=$(free_blocks $TEST_DIR)
	local FREE_INODES_PROJECT=$(free_inodes $TEST_DIR)
	local USED_BLOCKS_PROJECT=$(used_blocks $TEST_DIR)
	local USED_INODES_PROJECT=$(used_inodes $TEST_DIR)
	local USED_INODES_QUOTA=$($GETQUOTA -P $PROJECT $DEVICE curinodes)
	local USED_BLOCKS_QUOTA=$($GETQUOTA -P $PROJECT $DEVICE curspace)

	[ "$BLOCK_LIMIT_SOFT" != "$TOTAL_BLOCKS_PROJECT" ] &&
		error "block error with inherit and soft limit, expected $BLOCK_LIMIT_SOFT, got $TOTAL_BLOCKS_PROJECT"
	
	[ "$ILIMIT_SOFT" != "$TOTAL_INODES_PROJECT" ] &&
		error "inode error with inherit and soft limit, expected $ILIMIT_SOFT, got $TOTAL_INODES_PROJECT"

	[ "$USED_BLOCKS_PROJECT" != "$USED_BLOCKS_QUOTA" ] &&
		error "used block error with inherit, expected $USED_BLOCKS_QUOTA, got $USED_BLOCKS_PROJECT"
	
	[ "$USED_INODES_PROJECT" != "$USED_INODES_QUOTA" ] &&
		error "used inode error with inherit, expected $USED_INODES_QUOTA, got $USED_INODES_PROJECT"

	local SUM=$(expr $FREE_INODES_PROJECT + $USED_INODES_PROJECT )
	[ $SUM -ne $TOTAL_INODES_PROJECT ] &&
		error "Sum of free inodes($FREE_INODES_PROJECT) and used inodes($USED_INODES_PROJECT) is not equal to total inodes($TOTAL_INODES_PROJECT)"

	local SUM=$(expr $FREE_BLOCKS_PROJECT + $USED_BLOCKS_PROJECT )
	[ $SUM -ne $TOTAL_BLOCKS_PROJECT ] &&
		error "Sum of free blocks($FREE_BLOCKS_PROJECT) and used blocks($USED_BLOCKS_PROJECT) is not equal to total blocks($TOTAL_BLOCKS_PROJECT)"

	return 0
}
run_test 12 "statfs"

init_without_project() {
	MOUNTED=$(mount | grep $MNT | grep $DEVICE)
	if [ "$MOUNTED" != "" ]; then
		umount $MNT > /dev/null 2>&1
		if [ $? -ne 0 ]; then
			echo "Failed to umount $MNT"
			exit 1
		fi
	fi
	
	mkfs.ext4 -O quota $DEVICE -F
	if [ $? -ne 0 ]; then
		echo "Failed to mkfs.ext4 $DEVICE"
		exit 1
	fi
	
	mount $DEVICE -t ext4 $MNT > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "Failed to mount $DEVICE to $MNT"
		exit 1
	fi
	
	chmod 777 $MNT
	if [ $? -ne 0 ]; then
		echo "Failed to chmod $MNT"
		exit 1
	fi

	mkdir $TEST_DIR
	chmod 777 $TEST_DIR
	export PROJECT_ENABLED='no'
}

init_without_project

test_13() {
	getproject $TEST_DIR || error "getproject failure, expected success"
	$SETPROJECT -v $PROJECT $TEST_DIR && error "setproject to $PROJECT success, expected failure"
	$SETPROJECT -v $DEFAULT_PROJECT $TEST_DIR || error "setproject to $DEFAULT_PROJECT failure, expected success"
	set_inherit $TEST_DIR || error "set inherit failure, expected success"
	clear_inherit $TEST_DIR || error "Clear inherit failure, expected success"
	return 0
}
run_test 13 "Mount without project support"
