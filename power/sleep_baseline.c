/* Sleeps for 10 seconds, measuring the power consumption */
#include <unistd.h>
#include "power_rapl.h"

int main(int arc, char *argv[])
{
	power_rapl_t ps;
	power_rapl_init(&ps);
	power_rapl_start(&ps);
	sleep(10);
	power_rapl_end(&ps);
	// We print this at the end to facilitate parsing of the log files.
	printf("Monitoring baseline sleeping power for 10 seconds\n");
	power_rapl_print(&ps);
	return 0;
}

