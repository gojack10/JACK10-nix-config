// Root LaunchDaemon that reports the processes with the largest physical
// footprint, the value Activity Monitor shows as Memory. Only root can read it
// for every process. launchd owns the listening socket and starts this reader
// on the first connection; it answers only the user ID given as its argument.
#include <errno.h>
#include <launch.h>
#include <libproc.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <unistd.h>

#define REPORTED_PROCESSES 6

typedef struct { pid_t pid; uint64_t footprint; } Process;

static int larger_first(const void *left, const void *right) {
    uint64_t a = ((const Process *)left)->footprint, b = ((const Process *)right)->footprint;
    return (a < b) - (a > b);
}

// One line per process: PID, footprint in bytes and executable name, tab-separated.
static void report(int client) {
    int capacity = proc_listallpids(NULL, 0) + 64;
    pid_t *pids = calloc(capacity, sizeof(pid_t));
    Process *processes = calloc(capacity, sizeof(Process));
    int count = pids && processes ? proc_listallpids(pids, capacity * (int)sizeof(pid_t)) : 0;
    int found = 0;
    for (int i = 0; i < count; i++) {
        struct rusage_info_v4 usage;
        if (proc_pid_rusage(pids[i], RUSAGE_INFO_V4, (rusage_info_t *)&usage) == 0)
            processes[found++] = (Process){pids[i], usage.ri_phys_footprint};
    }
    qsort(processes, found, sizeof(Process), larger_first);
    for (int i = 0; i < found && i < REPORTED_PROCESSES; i++) {
        char path[PROC_PIDPATHINFO_MAXSIZE] = "";
        char *name = path;
        if (proc_pidpath(processes[i].pid, path, sizeof(path)) > 0) {
            char *slash = strrchr(path, '/');
            if (slash) name = slash + 1;
        } else {
            proc_name(processes[i].pid, path, sizeof(path));
        }
        for (char *c = name; *c; c++) if (*c == '\t' || *c == '\n' || *c == '\r') *c = ' ';
        dprintf(client, "%d\t%llu\t%s\n", processes[i].pid,
                (unsigned long long)processes[i].footprint, name[0] ? name : "-");
    }
    free(pids);
    free(processes);
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s UID\n", argv[0]);
        return 64;
    }
    uid_t allowed = (uid_t)strtoul(argv[1], NULL, 10);
    int *sockets = NULL;
    size_t count = 0;
    int error = launch_activate_socket("Listener", &sockets, &count);
    if (error || count != 1) {
        fprintf(stderr, "launch_activate_socket: %s\n", strerror(error ? error : EINVAL));
        return 1;
    }
    // A client that disconnects early must not terminate the reader.
    signal(SIGPIPE, SIG_IGN);
    for (;;) {
        int client = accept(sockets[0], NULL, NULL);
        if (client < 0) {
            if (errno == EINTR || errno == ECONNABORTED) continue;
            perror("accept");
            return 1;
        }
        uid_t uid;
        gid_t gid;
        if (getpeereid(client, &uid, &gid) == 0 && uid == allowed) report(client);
        close(client);
    }
}
