// SPDX-License-Identifier: MIT

#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define INPUT_SCAN_LIMIT 32
#define REOPEN_INTERVAL_MS 2000
#define REPEAT_DELAY_MS 450
#define REPEAT_INTERVAL_MS 120
#define PERSIST_DELAY_MS 750
#define PORTMASTER_EXIT_HOLD_MS 1000
#define POWER_MENU_DEBOUNCE_MS 800
#define VOLUME_MAX 12
#define VOLUME_DEFAULT 8

struct input_source {
    const char *name;
    int fd;
};

static volatile sig_atomic_t running = 1;
static volatile sig_atomic_t power_menu_requested = 0;

static void stop_running(int signal_number)
{
    (void)signal_number;
    running = 0;
}

static void request_power_menu(int signal_number)
{
    (void)signal_number;
    power_menu_requested = 1;
}

static long long monotonic_ms(void)
{
    struct timespec now;

    if (clock_gettime(CLOCK_MONOTONIC, &now) < 0)
        return 0;
    return (long long)now.tv_sec * 1000LL + now.tv_nsec / 1000000LL;
}

static int open_named_event(const char *target_name)
{
    char path[64];
    char name[256];
    int index;

    for (index = 0; index < INPUT_SCAN_LIMIT; index++) {
        int fd;

        snprintf(path, sizeof(path), "/dev/input/event%d", index);
        fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0)
            continue;
        memset(name, 0, sizeof(name));
        if (ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name) >= 0 &&
            strcmp(name, target_name) == 0) {
            fprintf(stderr, "hardware-keys: opened %s name=%s\n", path, name);
            return fd;
        }
        close(fd);
    }
    return -1;
}

static void reopen_source(struct input_source *source)
{
    if (source->fd >= 0)
        return;
    source->fd = open_named_event(source->name);
}

static int run_helper(const char *helper_name, const char *action)
{
    const char *root = getenv("PLUMOS_ROOT");
    char helper[512];
    pid_t child;
    int status = 0;
    pid_t waited;

    if (!root || !root[0])
        root = "/mnt/plumos";
    if (snprintf(helper, sizeof(helper), "%s/bin/%s", root, helper_name) >=
        (int)sizeof(helper))
        return -ENAMETOOLONG;

    child = fork();
    if (child < 0)
        return -errno;
    if (child == 0) {
        execl(helper, helper, action, (char *)NULL);
        _exit(127);
    }
    do {
        waited = waitpid(child, &status, 0);
    } while (waited < 0 && errno == EINTR);
    if (waited < 0)
        return -errno;
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
        return -EIO;
    return 0;
}

static int process_owns_fb0(pid_t pid)
{
    char directory_path[64];
    DIR *directory;
    struct dirent *entry;
    int owns_fb0 = 0;

    if (pid <= 1 || snprintf(directory_path, sizeof(directory_path),
                             "/proc/%ld/fd", (long)pid) >=
                        (int)sizeof(directory_path))
        return 0;
    directory = opendir(directory_path);
    if (!directory)
        return 0;
    while ((entry = readdir(directory)) != NULL) {
        char link_path[128];
        char target[128];
        ssize_t length;

        if (entry->d_name[0] == '.')
            continue;
        if (snprintf(link_path, sizeof(link_path), "%s/%s", directory_path,
                     entry->d_name) >= (int)sizeof(link_path))
            continue;
        length = readlink(link_path, target, sizeof(target) - 1);
        if (length < 0)
            continue;
        target[length] = '\0';
        if (strcmp(target, "/dev/fb0") == 0) {
            owns_fb0 = 1;
            break;
        }
    }
    closedir(directory);
    return owns_fb0;
}

static pid_t frontend_ready_pid(void)
{
    FILE *file = fopen("/tmp/plumos-fe-ready", "r");
    char line[64];
    long value = 0;

    if (!file)
        return 0;
    while (fgets(line, sizeof(line), file)) {
        if (sscanf(line, "pid=%ld", &value) == 1)
            break;
    }
    fclose(file);
    if (value <= 1 || kill((pid_t)value, 0) < 0)
        return 0;
    return (pid_t)value;
}

static int open_power_menu(int force_overlay)
{
    pid_t frontend_pid = frontend_ready_pid();
    int result;

    if (!force_overlay && frontend_pid > 0 && process_owns_fb0(frontend_pid)) {
        fprintf(stderr,
                "hardware-keys: action=power-menu delegated=frontend pid=%ld\n",
                (long)frontend_pid);
        return 0;
    }
    if (access("/run/plumos/power-menu-overlay.lock", F_OK) == 0) {
        fprintf(stderr, "hardware-keys: action=power-menu skipped=already-open\n");
        return 0;
    }
    result = run_helper("plumos-power-menu-overlay", "open");
    fprintf(stderr, "hardware-keys: action=power-menu overlay=1 rc=%d\n",
            result);
    return result;
}

static int read_volume_state(const char *path)
{
    char buffer[32];
    char *end;
    long value;
    int fd;
    ssize_t length;

    fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return VOLUME_DEFAULT;
    length = read(fd, buffer, sizeof(buffer) - 1);
    close(fd);
    if (length <= 0)
        return VOLUME_DEFAULT;
    buffer[length] = '\0';
    errno = 0;
    value = strtol(buffer, &end, 10);
    if (errno || end == buffer)
        return VOLUME_DEFAULT;
    if (value < 0)
        return 0;
    if (value > VOLUME_MAX)
        return VOLUME_MAX;
    return (int)value;
}

static int change_runtime_volume(const char *path, int direction)
{
    char temporary[512];
    char value[32];
    int current = read_volume_state(path);
    int next = current + (direction > 0 ? 1 : -1);
    int fd;
    int length;

    if (next < 0)
        next = 0;
    if (next > VOLUME_MAX)
        next = VOLUME_MAX;
    if (next == current)
        return 0;
    if (snprintf(temporary, sizeof(temporary), "%s.tmp.%ld", path,
                 (long)getpid()) >= (int)sizeof(temporary))
        return -ENAMETOOLONG;
    length = snprintf(value, sizeof(value), "%d\n", next);
    fd = open(temporary, O_CREAT | O_TRUNC | O_WRONLY | O_CLOEXEC, 0644);
    if (fd < 0)
        return -errno;
    if (write(fd, value, (size_t)length) != length) {
        int error = errno ? -errno : -EIO;
        close(fd);
        unlink(temporary);
        return error;
    }
    if (close(fd) < 0) {
        int error = -errno;
        unlink(temporary);
        return error;
    }
    if (rename(temporary, path) < 0) {
        int error = -errno;
        unlink(temporary);
        return error;
    }
    return 0;
}

static int apply_key_action(int direction, int select_down,
                            const char *volume_state_path)
{
    const char *helper;
    const char *action;
    int result;

    if (select_down) {
        helper = "plumos-display-control";
        action = direction > 0 ? "runtime-up" : "runtime-down";
        result = run_helper(helper, action);
    } else {
        result = change_runtime_volume(volume_state_path, direction);
    }
    fprintf(stderr, "hardware-keys: action=%s direction=%s rc=%d\n",
            select_down ? "display-lumination" : "volume",
            direction > 0 ? "up" : "down", result);
    return result;
}

static void persist_pending(int *volume_pending, int *display_pending)
{
    if (*volume_pending) {
        int result = run_helper("plumos-volume-control", "persist-runtime");
        fprintf(stderr, "hardware-keys: persist=volume rc=%d\n", result);
        if (result == 0)
            *volume_pending = 0;
    }
    if (*display_pending) {
        int result = run_helper("plumos-display-control", "persist-runtime");
        fprintf(stderr, "hardware-keys: persist=display-lumination rc=%d\n",
                result);
        if (result == 0)
            *display_pending = 0;
    }
}

int main(void)
{
    struct input_source gamepad = { "adc_gamepad", -1 };
    struct input_source volume_keys = { "sunxi-keyboard", -1 };
    struct input_source power_key = { "axp2202-pek", -1 };
    long long next_reopen = 0;
    long long repeat_due = 0;
    long long persist_due = 0;
    long long portmaster_exit_due = 0;
    long long power_menu_debounce_due = 0;
    int select_down = 0;
    int start_down = 0;
    int portmaster_exit_latched = 0;
    int held_direction = 0;
    int held_is_display = 0;
    int volume_pending = 0;
    int display_pending = 0;
    const char *runtime_root = getenv("PLUMOS_RUNTIME_ROOT");
    char lock_path[512];
    char volume_state_path[512];
    int lock_fd;

    if (!runtime_root || !runtime_root[0])
        runtime_root = "/run/plumos";
    if (snprintf(lock_path, sizeof(lock_path), "%s/hardware-keys/daemon.lock",
                 runtime_root) >= (int)sizeof(lock_path)) {
        fprintf(stderr, "hardware-keys: lock path is too long\n");
        return 1;
    }
    if (snprintf(volume_state_path, sizeof(volume_state_path),
                 "%s/volume/current", runtime_root) >=
        (int)sizeof(volume_state_path)) {
        fprintf(stderr, "hardware-keys: volume state path is too long\n");
        return 1;
    }
    lock_fd = open(lock_path, O_CREAT | O_RDWR | O_CLOEXEC, 0644);
    if (lock_fd < 0 || flock(lock_fd, LOCK_EX | LOCK_NB) < 0) {
        fprintf(stderr, "hardware-keys: another daemon owns the service lock\n");
        if (lock_fd >= 0)
            close(lock_fd);
        return 1;
    }

    signal(SIGINT, stop_running);
    signal(SIGTERM, stop_running);
    signal(SIGUSR1, request_power_menu);
    setvbuf(stderr, NULL, _IOLBF, 0);
    fprintf(stderr, "hardware-keys: starting pid=%ld\n", (long)getpid());

    (void)run_helper("plumos-volume-control", "apply");
    (void)run_helper("plumos-display-control", "apply");

    while (running) {
        struct pollfd poll_fds[3];
        struct input_source *sources[3] = { &gamepad, &volume_keys, &power_key };
        long long now = monotonic_ms();
        int timeout = 100;
        int index;
        int ready;

        if (now >= next_reopen) {
            reopen_source(&gamepad);
            reopen_source(&volume_keys);
            reopen_source(&power_key);
            next_reopen = now + REOPEN_INTERVAL_MS;
        }

        for (index = 0; index < 3; index++) {
            poll_fds[index].fd = sources[index]->fd;
            poll_fds[index].events = POLLIN;
            poll_fds[index].revents = 0;
        }
        ready = poll(poll_fds, 3, timeout);
        now = monotonic_ms();
        if (ready < 0 && errno != EINTR)
            fprintf(stderr, "hardware-keys: poll failed errno=%d\n", errno);

        if (power_menu_requested) {
            power_menu_requested = 0;
            (void)open_power_menu(1);
            now = monotonic_ms();
            power_menu_debounce_due = now + POWER_MENU_DEBOUNCE_MS;
        }

        for (index = 0; ready > 0 && index < 3; index++) {
            struct input_source *source = sources[index];

            if (source->fd < 0 || !(poll_fds[index].revents & (POLLIN | POLLERR | POLLHUP)))
                continue;
            for (;;) {
                struct input_event event;
                ssize_t bytes = read(source->fd, &event, sizeof(event));

                if (bytes == (ssize_t)sizeof(event)) {
                    if (source == &power_key && event.type == EV_KEY &&
                        event.code == KEY_POWER) {
                        if (event.value == 1 &&
                            now >= power_menu_debounce_due) {
                            (void)open_power_menu(0);
                            now = monotonic_ms();
                            power_menu_debounce_due =
                                now + POWER_MENU_DEBOUNCE_MS;
                        }
                    } else if (source == &gamepad && event.type == EV_KEY &&
                        (event.code == BTN_SELECT ||
                         event.code == BTN_START)) {
                        if (event.code == BTN_SELECT)
                            select_down = event.value != 0;
                        else
                            start_down = event.value != 0;

                        if (select_down && start_down) {
                            if (!portmaster_exit_latched &&
                                portmaster_exit_due == 0)
                                portmaster_exit_due =
                                    now + PORTMASTER_EXIT_HOLD_MS;
                        } else {
                            portmaster_exit_due = 0;
                            portmaster_exit_latched = 0;
                        }
                    } else if (source == &volume_keys && event.type == EV_KEY &&
                               (event.code == KEY_VOLUMEUP ||
                                event.code == KEY_VOLUMEDOWN)) {
                        int direction = event.code == KEY_VOLUMEUP ? 1 : -1;

                        if (event.value == 1) {
                            int result;

                            held_direction = direction;
                            held_is_display = select_down;
                            result = apply_key_action(direction, held_is_display,
                                                      volume_state_path);
                            if (result == 0) {
                                if (held_is_display)
                                    display_pending = 1;
                                else
                                    volume_pending = 1;
                                persist_due = now + PERSIST_DELAY_MS;
                            }
                            repeat_due = now + REPEAT_DELAY_MS;
                        } else if (event.value == 0 &&
                                   direction == held_direction) {
                            held_direction = 0;
                            repeat_due = 0;
                        }
                    }
                    continue;
                }
                if (bytes < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
                    break;
                if (bytes < 0 && errno == EINTR)
                    continue;
                fprintf(stderr, "hardware-keys: closed name=%s errno=%d\n",
                        source->name, bytes < 0 ? errno : 0);
                close(source->fd);
                source->fd = -1;
                if (source == &gamepad) {
                    select_down = 0;
                    start_down = 0;
                    portmaster_exit_due = 0;
                    portmaster_exit_latched = 0;
                }
                if (source == &volume_keys) {
                    held_direction = 0;
                    repeat_due = 0;
                }
                next_reopen = 0;
                break;
            }
        }

        now = monotonic_ms();
        if (!portmaster_exit_latched && portmaster_exit_due > 0 &&
            now >= portmaster_exit_due) {
            int result = run_helper("plumos-portmaster-port-stop", "stop");

            fprintf(stderr,
                    "hardware-keys: action=portmaster-force-exit rc=%d\n",
                    result);
            portmaster_exit_due = 0;
            portmaster_exit_latched = 1;
        }
        if (held_direction && repeat_due > 0 && now >= repeat_due) {
            int result = apply_key_action(held_direction, held_is_display,
                                          volume_state_path);

            if (result == 0) {
                if (held_is_display)
                    display_pending = 1;
                else
                    volume_pending = 1;
                persist_due = now + PERSIST_DELAY_MS;
            }
            repeat_due = now + REPEAT_INTERVAL_MS;
        }
        if ((volume_pending || display_pending) && persist_due > 0 &&
            now >= persist_due) {
            persist_pending(&volume_pending, &display_pending);
            persist_due = (volume_pending || display_pending)
                              ? now + PERSIST_DELAY_MS
                              : 0;
        }
    }

    persist_pending(&volume_pending, &display_pending);
    if (gamepad.fd >= 0)
        close(gamepad.fd);
    if (volume_keys.fd >= 0)
        close(volume_keys.fd);
    if (power_key.fd >= 0)
        close(power_key.fd);
    close(lock_fd);
    fprintf(stderr, "hardware-keys: stopped\n");
    return 0;
}
