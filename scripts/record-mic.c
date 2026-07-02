#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#ifndef FFMPEG_PATH
#define FFMPEG_PATH "ffmpeg"
#endif

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

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
    char command[PATH_MAX + 128];
    snprintf(command, sizeof(command), "%s -hide_banner -f avfoundation -list_devices true -i \"\" 2>&1", FFMPEG_PATH);

    FILE *fp = popen(command, "r");
    if (!fp) {
        fprintf(stderr, "record-mic: cannot run ffmpeg: %s\n", strerror(errno));
        return -1;
    }

    int audio = 0;
    int chosen_idx = -1;
    char line[1024];

    while (fgets(line, sizeof(line), fp)) {
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

    pclose(fp); /* ffmpeg returns non-zero for device listing; ignore it. */

    if (chosen_idx < 0) {
        fprintf(stderr, "record-mic: could not find %s microphone\n", use_airpods ? "AirPods" : "MacBook built-in");
        return -1;
    }
    return chosen_idx;
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

    char mic_name[512] = "";
    int mic_idx = choose_mic(use_airpods, mic_name, sizeof(mic_name));
    if (mic_idx < 0) return 1;

    char input[32];
    snprintf(input, sizeof(input), ":%d", mic_idx);

    printf("%s\n", out);
    fflush(stdout);
    fprintf(stderr, "Recording mic '%s' to: %s\n", mic_name, out);
    fprintf(stderr, "Press q or Ctrl-C to stop.\n");

    char *const ffmpeg_argv[] = {
        (char *)FFMPEG_PATH,
        "-hide_banner",
        "-y",
        "-thread_queue_size", "1024",
        "-f", "avfoundation",
        "-i", input,
        "-vn",
        "-ar", "48000",
        "-c:a", "libopus",
        "-b:a", "64k",
        out,
        NULL
    };

    execvp(FFMPEG_PATH, ffmpeg_argv);
    fprintf(stderr, "record-mic: exec ffmpeg failed: %s\n", strerror(errno));
    return 127;
}
