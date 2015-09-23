#ifndef __PROJECT__
#define __PROJECT__

#include <linux/types.h>

/*
 * Structure for FS_IOC_FSGETXATTR and FS_IOC_FSSETXATTR.
 */
struct fsxattr {
       __u32           fsx_xflags;     /* xflags field value (get/set) */
       __u32           fsx_extsize;    /* extsize field value (get/set)*/
       __u32           fsx_nextents;   /* nextents field value (get)   */
       __u32           fsx_projid;     /* project identifier (get/set) */
       unsigned char   fsx_pad[12];
};

#define EXT4_IOC_FSGETXATTR		_IOR('X', 31, struct fsxattr)
#define EXT4_IOC_FSSETXATTR		_IOW('X', 32, struct fsxattr)

#ifdef O_LARGEFILE
#define OPEN_FLAGS (O_RDONLY|O_NONBLOCK|O_LARGEFILE)
#else
#define OPEN_FLAGS (O_RDONLY|O_NONBLOCK)
#endif

int fgetproject(const char *name, int *project);
int fsetproject(const char *name, int project);

#define VERSION "0.1"
#endif /* __PROJECT__ */
