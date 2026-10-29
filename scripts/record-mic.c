#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#ifndef FFMPEG_PATH
#define FFMPEG_PATH "ffmpeg"
#endif

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#ifndef STARTUP_TIMEOUT_SECONDS
#define STARTUP_TIMEOUT_SECONDS 10
#endif

#ifndef SYSTEM_LOG_PATH
#define SYSTEM_LOG_PATH "/usr/bin/log"
#endif

static volatile sig_atomic_t interrupted;

static void handle_signal(int sig) {
    interrupted = sig;
}

static long long monotonic_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void stop_child(pid_t pid) {
    /* Give FFmpeg time to finalize audio after a terminal-delivered signal. */
    for (int phase = 0; phase < 2; phase++) {
        if (phase) kill(pid, SIGTERM);
        for (int i = 0; i < 50; i++) {
            pid_t done = waitpid(pid, NULL, WNOHANG);
            if (done == pid || (done < 0 && errno != EINTR)) return;
            usleep(10000);
        }
    }
    kill(pid, SIGKILL);
    while (waitpid(pid, NULL, 0) < 0 && errno == EINTR) {}
}

static void audio_diagnostics(pid_t pid, const char *started) {
    char predicate[256];
    snprintf(predicate, sizeof(predicate),
             "(processID == %d OR process == \"coreaudiod\") AND "
             "(messageType == error OR messageType == fault)", (int)pid);
    fprintf(stderr, "record-mic: macOS audio errors since %s (recorder PID %d):\n", started, (int)pid);
    fflush(stderr);
    pid_t logger = fork();
    if (logger == 0) {
        dup2(STDERR_FILENO, STDOUT_FILENO);
        execl(SYSTEM_LOG_PATH, SYSTEM_LOG_PATH, "show", "--start", started,
              "--style", "compact", "--predicate", predicate, (char *)NULL);
        perror("record-mic: cannot read macOS audio log");
        _exit(127);
    }
    if (logger < 0) {
        perror("record-mic: cannot launch audio diagnostics");
        return;
    }
    long long deadline = monotonic_ms() + 3000;
    for (;;) {
        pid_t done = waitpid(logger, NULL, WNOHANG);
        if (done == logger || (done < 0 && errno != EINTR)) break;
        if (monotonic_ms() >= deadline || interrupted) {
            kill(logger, SIGKILL);
            while (waitpid(logger, NULL, 0) < 0 && errno == EINTR) {}
            fprintf(stderr, "record-mic: audio log collection interrupted or exceeded 3 seconds.\n");
            break;
        }
        usleep(10000);
    }
}

static void usage(const char *prog) {
    fprintf(stderr, "usage: %s [--airpods] [--dir DIR]\n", prog);
    fprintf(stderr, "records the MacBook built-in mic to DIR/mic-YYYYmmdd-HHMMSS.opus; default DIR is /tmp\n");
    fprintf(stderr, "prints the output path on stdout so you can run: record-mic | transcribe --tmp\n");
    fprintf(stderr, "pass --airpods to record the AirPods mic instead\n");
}

static int contains_ci(const char *haystack, const char *needle) {
    if (!*needle) return 1;
    for (; *haystack; haystack++) {
        const char *h = haystack;
        const char *n = needle;
        while (*h && *n && tolower((unsigned char)*h) == tolower((unsigned char)*n)) {
            h++;
            n++;
        }
        if (!*n) return 1;
    }
    return 0;
}

static int is_builtin_mic(const char *name) {
    return !contains_ci(name, "airpods") &&
           !contains_ci(name, "blackhole") &&
           ((contains_ci(name, "macbook") && contains_ci(name, "microphone")) ||
            (contains_ci(name, "built") && contains_ci(name, "microphone")));
}

static int is_airpods_mic(const char *name) {
    return contains_ci(name, "airpods") && !contains_ci(name, "blackhole");
}

static int parse_device_line(const char *line, int *idx, char *name, size_t name_len) {
    const char *p = line;
    while ((p = strchr(p, '[')) != NULL) {
        p++;
        if (!isdigit((unsigned char)*p)) continue;

        char *end = NULL;
        long value = strtol(p, &end, 10);
        if (!end || *end != ']' || value < 0) continue;

        const char *device_name = end + 1;
        while (*device_name == ' ' || *device_name == '\t') device_name++;
        if (!*device_name) return 0;

        size_t len = strcspn(device_name, "\r\n");
        if (len >= name_len) len = name_len - 1;
        memcpy(name, device_name, len);
        name[len] = '\0';
        *idx = (int)value;
        return 1;
    }
    return 0;
}

static int choose_mic(int use_airpods, char *chosen_name, size_t chosen_name_len) {
    int fds[2];
    if (pipe(fds) < 0) {
        perror("record-mic: device-list pipe");
        return -1;
    }
    pid_t pid = fork();
    if (pid == 0) {
        close(fds[0]);
        dup2(fds[1], STDERR_FILENO);
        close(fds[1]);
        execlp(FFMPEG_PATH, FFMPEG_PATH, "-hide_banner", "-f", "avfoundation",
              "-list_devices", "true", "-i", "", (char *)NULL);
        perror("record-mic: device listing exec failed");
        _exit(127);
    }
    close(fds[1]);
    if (pid < 0) {
        close(fds[0]);
        perror("record-mic: device listing fork failed");
        return -1;
    }

    int audio = 0;
    int chosen_idx = -1;
    char line[1024];
    size_t used = 0;
    long long deadline = monotonic_ms() + STARTUP_TIMEOUT_SECONDS * 1000;

    while (!interrupted) {
        if (monotonic_ms() >= deadline) {
            fprintf(stderr, "record-mic: microphone discovery timed out after %d seconds.\n", STARTUP_TIMEOUT_SECONDS);
            break;
        }
        struct pollfd pfd = {.fd = fds[0], .events = POLLIN};
        int polled = poll(&pfd, 1, 100);
        if (polled < 0 && errno == EINTR) continue;
        if (polled < 0) { perror("record-mic: device listing poll"); break; }
        if (!polled) continue;
        char c;
        if (read(fds[0], &c, 1) != 1) break;
        if (c != '\n' && used < sizeof(line) - 1) {
            line[used++] = c;
            continue;
        }
        line[used] = '\0';
        used = 0;
        fprintf(stderr, "%s\n", line);
        if (strstr(line, "AVFoundation video devices:")) {
            audio = 0;
            continue;
        }
        if (strstr(line, "AVFoundation audio devices:")) {
            audio = 1;
            continue;
        }
        if (!audio) continue;

        int idx = -1;
        char name[512];
        if (!parse_device_line(line, &idx, name, sizeof(name))) continue;

        if ((use_airpods && is_airpods_mic(name)) || (!use_airpods && is_builtin_mic(name))) {
            chosen_idx = idx;
            snprintf(chosen_name, chosen_name_len, "%s", name);
            break;
        }
    }

    close(fds[0]);
    stop_child(pid); /* Device listing intentionally returns nonzero. */

    if (chosen_idx < 0) {
        fprintf(stderr, "record-mic: could not find %s microphone\n", use_airpods ? "AirPods" : "MacBook built-in");
        return -1;
    }
    return chosen_idx;
}

static int record_audio(const char *input, const char *out,
                        const char *mic_name, const char *started) {
    int fds[2];
    if (pipe(fds) < 0) { perror("record-mic: progress pipe"); return 1; }
    char progress[32];
    snprintf(progress, sizeof(progress), "pipe:%d", fds[1]);
    char *const argv[] = {
        (char *)FFMPEG_PATH,
        "-progress", progress,
        "-stats_period", "0.1",
        "-hide_banner",
        "-y",
        "-thread_queue_size", "1024",
        "-f", "avfoundation",
        "-i", (char *)input,
        "-vn",
        "-ar", "48000",
        "-c:a", "libopus",
        "-b:a", "64k",
        "-page_duration", "100000",
        "-flush_packets", "1",
        (char *)out,
        NULL
    };
    pid_t pid = fork();
    if (pid == 0) {
        close(fds[0]);
        signal(SIGINT, SIG_DFL);
        signal(SIGTERM, SIG_DFL);
        signal(SIGHUP, SIG_DFL);
        execvp(FFMPEG_PATH, argv);
        perror("record-mic: exec ffmpeg failed");
        _exit(127);
    }
    close(fds[1]);
    if (pid < 0) {
        close(fds[0]);
        perror("record-mic: recording fork failed");
        return 1;
    }
    fprintf(stderr, "Opening mic '%s'; startup must succeed within %d seconds.\n", mic_name, STARTUP_TIMEOUT_SECONDS);
    long long deadline = monotonic_ms() + STARTUP_TIMEOUT_SECONDS * 1000;
    char line[256];
    size_t used = 0;
    long long audio_us = 0, output_bytes = 0;
    int ready = 0, status = 0, failed = 0;
    for (;;) {
        if (interrupted) {
            stop_child(pid);
            status = 128 + interrupted;
            break;
        }
        if (!ready && monotonic_ms() >= deadline) {
            fprintf(stderr, "\nrecord-mic: STARTUP FAILED: no saved audio after %d seconds.\n", STARTUP_TIMEOUT_SECONDS);
            stop_child(pid);
            failed = 1;
            status = 1;
            break;
        }
        struct pollfd pfd = {.fd = fds[0], .events = POLLIN};
        int polled = poll(&pfd, 1, 100);
        if (polled < 0 && errno == EINTR) continue;
        if (polled < 0) {
            perror("record-mic: progress poll");
            stop_child(pid);
            failed = 1;
            status = 1;
            break;
        }
        if (polled > 0) {
            char buf[4096];
            ssize_t n = read(fds[0], buf, sizeof(buf));
            for (ssize_t i = 0; i < n; i++) {
                if (buf[i] != '\n' && used < sizeof(line) - 1) {
                    line[used++] = buf[i];
                    continue;
                }
                line[used] = '\0';
                used = 0;
                if (!strncmp(line, "out_time_us=", 12)) audio_us = strtoll(line + 12, NULL, 10);
                if (!strncmp(line, "total_size=", 11)) output_bytes = strtoll(line + 11, NULL, 10);
            }
            struct stat st;
            /* At least one 100ms Ogg audio page, flushed to the output file. */
            if (!ready && audio_us >= 100000 && output_bytes > 0 &&
                stat(out, &st) == 0 && st.st_size >= output_bytes) {
                if (printf("%s\n", out) < 0 || fflush(stdout) == EOF) {
                    perror("record-mic: cannot deliver audio path to downstream command");
                    stop_child(pid);
                    failed = 1;
                    status = 1;
                    break;
                }
                ready = 1;
                fprintf(stderr, "\nRecording mic '%s' to: %s\nPress q or Ctrl-C to stop.\n", mic_name, out);
            }
            if (n == 0) {
                /* EOF without process exit is still subject to the deadline. */
                usleep(10000);
            }
        }
        pid_t done = waitpid(pid, &status, WNOHANG);
        if (done == pid) {
            status = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
            failed = !ready || status != 0;
            break;
        }
        if (done < 0 && errno != EINTR) {
            perror("record-mic: waitpid");
            failed = 1;
            status = 1;
            break;
        }
    }
    close(fds[0]);
    if (failed) {
        fprintf(stderr, "record-mic: %s (exit %d). FFmpeg stderr is shown above.\n",
                ready ? "recording failed" : "recording did not start", status);
        audio_diagnostics(pid, started);
        if (!status) status = 1;
    }
    if (ready || access(out, F_OK) == 0)
        fprintf(stderr, "record-mic: keeping audio at %s\n", out);
    if (interrupted) return 128 + interrupted;
    return status;
}

int main(int argc, char **argv) {
    const char *dir = "/tmp";
    int use_airpods = 0;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--airpods")) {
            use_airpods = 1;
        } else if (!strcmp(argv[i], "--dir")) {
            if (++i >= argc) {
                usage(argv[0]);
                return 2;
            }
            dir = argv[i];
        } else if (!strncmp(argv[i], "--dir=", 6)) {
            dir = argv[i] + 6;
        } else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) {
            usage(argv[0]);
            return 0;
        } else {
            usage(argv[0]);
            return 2;
        }
    }

    struct stat st;
    if (stat(dir, &st) != 0 || !S_ISDIR(st.st_mode)) {
        fprintf(stderr, "record-mic: not a directory: %s\n", dir);
        return 1;
    }

    time_t now = time(NULL);
    struct tm tm;
    if (!localtime_r(&now, &tm)) {
        perror("record-mic: localtime");
        return 1;
    }

    char stamp[32];
    if (!strftime(stamp, sizeof(stamp), "%Y%m%d-%H%M%S", &tm)) {
        fprintf(stderr, "record-mic: timestamp failed\n");
        return 1;
    }

    char out[PATH_MAX];
    if (snprintf(out, sizeof(out), "%s/mic-%s.opus", dir, stamp) >= (int)sizeof(out)) {
        fprintf(stderr, "record-mic: output path too long\n");
        return 1;
    }

    struct sigaction sa = {.sa_handler = handle_signal};
    sigemptyset(&sa.sa_mask);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGHUP, &sa, NULL);
    signal(SIGPIPE, SIG_IGN);

    char started[32];
    strftime(started, sizeof(started), "%Y-%m-%d %H:%M:%S", &tm);
    char mic_name[512] = "";
    int mic_idx = choose_mic(use_airpods, mic_name, sizeof(mic_name));
    if (mic_idx < 0) return interrupted ? 128 + interrupted : 1;

    char input[32];
    snprintf(input, sizeof(input), ":%d", mic_idx);

    return record_audio(input, out, mic_name, started);
}
