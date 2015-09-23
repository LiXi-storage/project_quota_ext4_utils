#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>
#include <libgen.h>
#include "project.h"

struct option long_options[] = {
	{ "help",		0, 0, 'H' },
	{ "only-values",	0, 0, 'v' },
	{ "version",		0, 0, 'V' },
	{ NULL,			0, 0, 0 }
};

const char *progname;

void help(void)
{
	printf("%s %s -- get project indentifier\n", progname, VERSION);
	printf("Usage: %s [-v value] [-h] file...\n", progname);
	printf(
"  -v, --only-values       use value as the project indentifier\n"
"      --version           print version and exit\n"
"      --help              this help text\n");
}

int main(int argc, char **argv)
{
	int project;
	int value_only = 0;
	int ret;
	int error_number = 0;
	int opt;

	progname = basename(argv[0]);

	while ((opt = getopt_long(argc, argv, "HvV",
				  long_options, NULL)) != -1) {
		switch(opt) {
		case 'v':
			value_only++;
			break;
		case 'V':
			printf("%s " VERSION "\n", progname);
			return 0;
		case 'H':
			help();
			return 0;
		default:
			help();
			return 2;
		}
	}

	if (optind >= argc) {
		help();
		return 2;
	}

	while (optind < argc) {
		ret = fgetproject(argv[optind], &project);
		if (ret < 0) {
			fprintf(stderr, "failed to get project of %s: %s\n",
				argv[optind], strerror(errno));
			error_number++;
		} else {
			if (value_only)
				printf("%u\n", project);
			else
				printf("Project of \"%s\" is %u\n",
				       argv[optind], project);
		}
		optind++;
	}

	return error_number ? 1 : 0;
}
