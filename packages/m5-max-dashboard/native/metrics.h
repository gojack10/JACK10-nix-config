#ifndef M5_MAX_METRICS_H
#define M5_MAX_METRICS_H

// Call sequentially. Returns UTF-8 JSON; unavailable readings are null.
// Full sampling includes thermals, fans and top CPU processes. Summary sampling
// omits those expensive reads for the closed menu-bar title.
void m5_sample(char *buffer, int capacity, int full);

#endif
