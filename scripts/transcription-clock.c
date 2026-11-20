/* Bash has no subsecond monotonic clock. This probe is used only by F5 traces. */
#include <inttypes.h>
#include <stdio.h>
#include <time.h>

int main(void) {
    printf("%" PRIu64 "\n", clock_gettime_nsec_np(CLOCK_UPTIME_RAW));
    return 0;
}
