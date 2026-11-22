#ifndef M5_MAX_METRICS_H
#define M5_MAX_METRICS_H

// Call sequentially. Returns UTF-8 JSON; unavailable readings are null.
// Full sampling includes GPU, per-core CPU, thermals, fans, top CPU, top memory and the charge limit.
// Summary sampling omits those reads for the closed menu-bar title.
void m5_sample(char *buffer, int capacity, int full);

// Configured manual charge ceiling. 100 = disabled; NaN = unavailable.
double m5_charge_limit_pct(void);

// Optional root LaunchDaemon that reports per-process physical footprint.
#define M5_MEMORY_READER_LABEL "com.jack.m5-max-dashboard.memory"
#define M5_MEMORY_READER_SOCKET "/var/run/com.jack.m5-max-dashboard.memory.sock"

#endif
