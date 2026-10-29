/* The terminal owns interaction; Launch Services owns microphone permission. */
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#ifndef RECORD_MIC_APP
#define RECORD_MIC_APP "Record Mic.app"
#endif

static volatile sig_atomic_t interrupted;
static struct termios saved_terminal;
static int restore_terminal;

static void handle_signal(int sig) { interrupted = sig; }
static void restore_input(void) {
    if (restore_terminal) tcsetattr(STDIN_FILENO, TCSANOW, &saved_terminal);
}
static long long now_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (long long)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}
static int copy_file(const char *path) {
    FILE *file = fopen(path, "r");
    if (!file) return -1;
    char buf[4096];
    size_t n;
    int failed = 0;
    while ((n = fread(buf, 1, sizeof(buf), file)))
        if (fwrite(buf, 1, n, stdout) != n) { failed = 1; break; }
    failed |= ferror(file) || fflush(stdout) == EOF;
    fclose(file);
    return failed ? -1 : 0;
}

int main(int argc, char **argv) {
    /* Reject bad arguments without launching an app or asking for permission. */
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--help") || !strcmp(argv[i], "-h")) {
            fprintf(stderr, "usage: record-mic [--airpods] [--dir DIR]\n"
                    "Records the built-in mic (or AirPods) to an Opus file.\n"
                    "Press q or Ctrl-C to stop; stdout contains only the completed path.\n"
                    "Record Mic asks for its own macOS microphone permission.\n");
            return 0;
        }
        if (!strcmp(argv[i], "--airpods")) continue;
        if (!strcmp(argv[i], "--dir") && i + 1 < argc) { i++; continue; }
        if (!strncmp(argv[i], "--dir=", 6) && argv[i][6]) continue;
        fprintf(stderr, "record-mic: invalid argument: %s (see --help)\n", argv[i]);
        return 2;
    }

    struct sigaction sa = {.sa_handler = handle_signal};
    sigemptyset(&sa.sa_mask);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGHUP, &sa, NULL);
    signal(SIGPIPE, SIG_IGN);
    atexit(restore_input);

    char request[] = "/tmp/record-mic-XXXXXXXX";
    if (!mkdtemp(request)) { perror("record-mic: request directory"); return 1; }
    char socket_path[PATH_MAX], result_path[PATH_MAX], status_path[PATH_MAX];
    snprintf(socket_path, sizeof(socket_path), "%s/control", request);
    snprintf(result_path, sizeof(result_path), "%s/result", request);
    snprintf(status_path, sizeof(status_path), "%s/status", request);
    int listener = -1, connection = -1, status = 1;
    pid_t helper = -1, launcher = -1;
    char **args = NULL;
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    snprintf(address.sun_path, sizeof(address.sun_path), "%s", socket_path);
    listener = socket(AF_UNIX, SOCK_STREAM, 0);
    if (listener < 0 || bind(listener, (struct sockaddr *)&address, sizeof(address)) < 0 ||
        listen(listener, 1) < 0) {
        perror("record-mic: control socket"); goto cleanup;
    }
    fcntl(listener, F_SETFD, FD_CLOEXEC);

    /* Relative output directories must remain relative to the invoking shell. */
    char cwd[PATH_MAX];
    if (!getcwd(cwd, sizeof(cwd))) { perror("record-mic: working directory"); goto cleanup; }
    args = calloc((size_t)argc + 12, sizeof(char *));
    if (!args) { perror("record-mic: launch arguments"); goto cleanup; }
    int n = 0;
    args[n++] = "/usr/bin/open";
    args[n++] = "-n";
    args[n++] = "-g";
    args[n++] = "-a";
    args[n++] = RECORD_MIC_APP;
    args[n++] = "--args";
    args[n++] = "--request";
    args[n++] = request;
    args[n++] = "--cwd";
    args[n++] = cwd;
    for (int i = 1; i < argc; i++) args[n++] = argv[i];
    launcher = fork();
    if (launcher == 0) {
        /* open must never send launch messages down the transcription pipe. */
        dup2(STDERR_FILENO, STDOUT_FILENO);
        execv(args[0], args);
        perror("record-mic: Launch Services"); _exit(127);
    }
    if (launcher < 0) { perror("record-mic: launch"); goto cleanup; }
    long long deadline = now_ms() + 10000;
    while (!interrupted && now_ms() < deadline) {
        struct pollfd fd = {.fd = listener, .events = POLLIN};
        if (poll(&fd, 1, 100) > 0) { connection = accept(listener, NULL, NULL); break; }
        int exit_status;
        if (launcher > 0 && waitpid(launcher, &exit_status, WNOHANG) == launcher) {
            launcher = -1;
            if (!WIFEXITED(exit_status) || WEXITSTATUS(exit_status) != 0) {
                fprintf(stderr, "record-mic: could not launch Record Mic in the logged-in desktop.\n");
                goto cleanup;
            }
        }
    }
    if (connection < 0) {
        fprintf(stderr, "record-mic: helper did not connect within 10 seconds; a logged-in macOS desktop is required.\n");
        goto cleanup;
    }
    uid_t uid; gid_t gid;
    socklen_t pid_size = sizeof(helper);
    if (getpeereid(connection, &uid, &gid) < 0 || uid != getuid() ||
        getsockopt(connection, SOL_LOCAL, LOCAL_PEERPID, &helper, &pid_size) < 0 || helper <= 1) {
        fprintf(stderr, "record-mic: cannot identify the local helper.\n"); helper = -1; goto cleanup;
    }
    fcntl(connection, F_SETFD, FD_CLOEXEC);
    if (isatty(STDIN_FILENO) && tcgetattr(STDIN_FILENO, &saved_terminal) == 0) {
        struct termios input = saved_terminal;
        input.c_lflag &= ~(ICANON | ECHO);
        input.c_cc[VMIN] = 1;
        input.c_cc[VTIME] = 0;
        if (tcsetattr(STDIN_FILENO, TCSANOW, &input) == 0) restore_terminal = 1;
    }
    int input_open = 1, sent_signal = 0;
    long long stop_deadline = 0;
    for (;;) {
        if (interrupted && !sent_signal) {
            kill(helper, interrupted);
            sent_signal = 1;
            stop_deadline = now_ms() + 5000;
        }
        if (stop_deadline && now_ms() >= stop_deadline) {
            fprintf(stderr, "record-mic: helper did not stop within 5 seconds.\n");
            goto cleanup;
        }
        struct pollfd fds[2] = {
            {.fd = connection, .events = POLLIN},
            {.fd = input_open ? STDIN_FILENO : -1, .events = POLLIN}
        };
        int ready = poll(fds, 2, 100);
        if (ready < 0 && errno == EINTR) continue;
        if (ready < 0) { perror("record-mic: control poll"); goto cleanup; }
        if (fds[0].revents & (POLLIN | POLLHUP | POLLERR)) {
            char buf[8192];
            ssize_t count = read(connection, buf, sizeof(buf));
            if (count == 0) break;
            if (count < 0) { if (errno == EINTR) continue; goto cleanup; }
            if (fwrite(buf, 1, (size_t)count, stderr) != (size_t)count) goto cleanup;
            fflush(stderr);
        }
        if (fds[1].revents & (POLLIN | POLLHUP)) {
            char buf[256];
            ssize_t count = read(STDIN_FILENO, buf, sizeof(buf));
            if (count <= 0) { input_open = 0; continue; }
            if (send(connection, buf, (size_t)count, 0) != count) goto cleanup;
            if (memchr(buf, 'q', (size_t)count)) {
                input_open = 0;
                stop_deadline = now_ms() + 5000;
            }
        }
    }
    FILE *receipt = fopen(status_path, "r");
    if (!receipt || fscanf(receipt, "%d", &status) != 1) {
        fprintf(stderr, "record-mic: helper exited without a completion status; no recording published.\n");
        status = 1;
    }
    if (receipt) fclose(receipt);
    helper = -1;
    if ((status == 0 || status == 130) && copy_file(result_path) < 0) {
        perror("record-mic: cannot deliver completed audio path"); status = 1;
    }
cleanup:
    restore_input();
    restore_terminal = 0;
    if (helper > 1) kill(helper, SIGTERM);
    if (connection >= 0) close(connection);
    if (listener >= 0) close(listener);
    if (launcher > 0) { kill(launcher, SIGTERM); while (waitpid(launcher, NULL, 0) < 0 && errno == EINTR) {} }
    free(args);
    unlink(socket_path); unlink(result_path); unlink(status_path); rmdir(request);
    return interrupted ? 128 + interrupted : status;
}
