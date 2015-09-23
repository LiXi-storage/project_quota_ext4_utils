#!/bin/bash
patches_applied()
{
	local SOURCE_DIR="$1"
	local EXPECTED_PATCHES="$2"
	local PATCHES=$(cd $SOURCE_DIR && quilt applied)
	for EXPECTED_PATCH in $EXPECTED_PATCHES; do
		FIND=0
		for PATCH in $PATCHES; do
			if [ "patches/$EXPECTED_PATCH" = "$PATCH" ]; then
				FIND=1
				break;
			fi
		done
		if [ $FIND -ne 1 ]; then
			echo "$EXPECTED_PATCH is not applied in $SOURCE_DIR"
			exit 1
		fi
	done
	echo "All expected patches are applied in $SOURCE_DIR"
}

patches_applied linux.git "general-project-quota.patch
ext4-project-ID.patch
ext4-project-quota.patch
ext4-project-ID-ioctl-interface.patch"

patches_applied e2fsprogs.git "e2fsprogs_rpm.patch
general_quota_support.patch
project_quota_support.patch
project_feature.patch
iherit_flag.patch"

patches_applied quota-tools.git "project_quota_support_for_quota-tools.patch
add_spec.patch
fix_str2number.patch
"

echo "Building quota-tools.git"
cd quota-tools.git
aclocal
if [ $? -ne 0 ]; then
	echo "failed to aclocal quota-tools.git"
	exit 1
fi
autoheader
if [ $? -ne 0 ]; then
	echo "failed to autoheader quota-tools.git"
	exit 1
fi
autoconf
if [ $? -ne 0 ]; then
	echo "failed to autoconf quota-tools.git"
	exit 1
fi
./configure > /dev/null 2>&1
if [ $? -ne 0 ]; then
	echo "failed to configure quota-tools.git"
	exit 1
fi
make > /dev/null 2>&1
if [ $? -ne 0 ]; then
	make
	echo "failed to make quota-tools.git"
	exit 1
fi
echo "Built quota-tools.git"

echo "Making rpm of quota-tools.git"
cd ..
rm quota-tools -fr
rm quota-4.01.tar.gz -f
cp quota-tools.git/ quota-tools -a
tar czf quota-4.01.tar.gz quota-tools
rpmbuild -ta quota-4.01.tar.gz
rm quota-tools -fr
rm quota-4.01.tar.gz -f
echo "Made rpm of quota-tools.git"
exit 0

cd e2fsprogs.git
./configure --enable-elf-shlibs --enable-nls --disable-uuidd --disable-fsck --disable-e2initrd-helper --disable-libblkid --disable-libuuid --disable-defrag --enable-symlink-install --enable-quota
make
make rpm
