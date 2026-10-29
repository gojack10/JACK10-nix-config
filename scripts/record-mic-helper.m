#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/un.h>

static int control_socket = -1;
static int controller_connected(void) {
    if (control_socket < 0) return 1; /* Standalone permission request. */
    char byte;
    ssize_t n = recv(control_socket, &byte, 1, MSG_PEEK | MSG_DONTWAIT);
    return n > 0 || (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR));
}

#define MICROPHONE_ACCESS_ALLOWED() ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusAuthorized)
#define CONTROLLER_CONNECTED() controller_connected()
#define main record_mic_main
#include "record-mic.c"
#undef main

static int authorize_microphone(void) {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (status == AVAuthorizationStatusNotDetermined) {
        fprintf(stderr, "record-mic: allow Record Mic in the macOS microphone prompt (waiting up to 60 seconds).\n");
        __block BOOL answered = NO;
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
            (void)granted;
            dispatch_async(dispatch_get_main_queue(), ^{ answered = YES; });
        }];
        long long deadline = monotonic_ms() + 60000;
        while (!answered && !interrupted && controller_connected() && monotonic_ms() < deadline) {
            /* q also cancels a pending prompt; it must not start a capture later. */
            char bytes[64];
            ssize_t count = recv(control_socket, bytes, sizeof(bytes), MSG_DONTWAIT);
            if (count > 0 && memchr(bytes, 'q', (size_t)count)) interrupted = SIGINT;
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        if (interrupted || !controller_connected()) return 1;
        if (!answered) {
            fprintf(stderr, "record-mic: microphone approval timed out; no capture started.\n");
            return 1;
        }
        status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    }
    if (status != AVAuthorizationStatusAuthorized) {
        fprintf(stderr, "record-mic: microphone access %s for Record Mic.\n"
                "Enable Record Mic in System Settings > Privacy & Security > Microphone, then rerun the command.\n",
                status == AVAuthorizationStatusRestricted ? "is restricted" : "was denied");
        return 1;
    }
    return 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        if (argc == 2 && !strcmp(argv[1], "--authorize")) return authorize_microphone();
        /* Opening the app alone is inert: no permission prompt and no mic. */
        if (argc < 5 || strcmp(argv[1], "--request") || strcmp(argv[3], "--cwd")) return 0;
        const char *request = argv[2];
        struct stat st;
        if (lstat(request, &st) < 0 || !S_ISDIR(st.st_mode) ||
            st.st_uid != getuid() || (st.st_mode & 0777) != 0700) return 1;
        struct sockaddr_un address = {.sun_family = AF_UNIX};
        if (snprintf(address.sun_path, sizeof(address.sun_path), "%s/control", request) >= (int)sizeof(address.sun_path)) return 1;
        control_socket = socket(AF_UNIX, SOCK_STREAM, 0);
        if (control_socket < 0 || connect(control_socket, (struct sockaddr *)&address, sizeof(address)) < 0) return 1;
        uid_t uid; gid_t gid;
        if (getpeereid(control_socket, &uid, &gid) < 0 || uid != getuid()) return 1;
        fcntl(control_socket, F_SETFD, FD_CLOEXEC);
        dup2(control_socket, STDIN_FILENO);
        dup2(control_socket, STDERR_FILENO);
        char result_path[PATH_MAX], status_path[PATH_MAX];
        snprintf(result_path, sizeof(result_path), "%s/result", request);
        snprintf(status_path, sizeof(status_path), "%s/status", request);
        int result = open(result_path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
        if (result < 0) return 1;
        dup2(result, STDOUT_FILENO);
        close(result);
        struct sigaction sa = {.sa_handler = handle_signal};
        sigemptyset(&sa.sa_mask);
        sigaction(SIGINT, &sa, NULL);
        sigaction(SIGTERM, &sa, NULL);
        sigaction(SIGHUP, &sa, NULL);
        signal(SIGPIPE, SIG_IGN);

        int status = 1;
        if (chdir(argv[4]) < 0) perror("record-mic: working directory");
        else if (authorize_microphone() == 0 && !interrupted && controller_connected()) {
            argv[4] = argv[0];
            status = record_mic_main(argc - 4, argv + 4);
        }
        if (interrupted) status = 128 + interrupted;
        fflush(stdout);
        int receipt = open(status_path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
        if (receipt >= 0) {
            dprintf(receipt, "%d\n", status);
            close(receipt);
        }
        /* EOF tells the terminal that both the result and exit status are final. */
        shutdown(control_socket, SHUT_RDWR);
        close(control_socket);
        return status;
    }
}
