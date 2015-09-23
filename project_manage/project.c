#include <stdio.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include "project.h"

int fgetproject(const char *name, int *project)
{
	struct stat buf;
	int fd;
	int ret;
	int save_errno = 0;
	struct fsxattr fsxattr;

	if (stat(name, &buf) == -1)
		return -1;

	fd = open(name, OPEN_FLAGS);
	if (fd == -1)
		return -1;

	ret = ioctl(fd, EXT4_IOC_FSGETXATTR, &fsxattr);
	if (ret < 0) {
		save_errno = errno;
		ret = -1;
	}

	close(fd);
	if (save_errno)
		errno = save_errno;
	if (ret >= 0)
		*project = fsxattr.fsx_projid;
	return ret;
}

int fsetproject(const char *name, int project)
{
	struct stat buf;
	int fd;
	int ret;
	int save_errno = 0;
	struct fsxattr fsxattr;

	if (stat(name, &buf) == -1)
		return -1;

	fd = open(name, OPEN_FLAGS);
	if (fd == -1)
		return -1;

	ret = ioctl(fd, EXT4_IOC_FSGETXATTR, &fsxattr);
	if (ret < 0) {
		save_errno = errno;
		ret = -1;
		goto out;
	}

	fsxattr.fsx_projid = project;

	ret = ioctl(fd, EXT4_IOC_FSSETXATTR, &fsxattr);
	if (ret < 0) {
		save_errno = errno;
		ret = -1;
		goto out;
	}

out:
	close(fd);
	if (save_errno)
		errno = save_errno;
	return ret;
}
