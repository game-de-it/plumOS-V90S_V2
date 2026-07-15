// SPDX-License-Identifier: MIT

#define _GNU_SOURCE
#include <alsa/asoundlib.h>
#include <alsa/pcm_external.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define INTERNAL_CARD 0
#define MAX_CARD_INDEX 15
#define USB_PROBE_INTERVAL 8

typedef struct {
    snd_pcm_ioplug_t io;
    snd_pcm_t *physical;
    int physical_card;
    int physical_is_usb;
    int poll_pipe[2];
    snd_pcm_uframes_t hw_ptr;
    int16_t *output_buffer;
    size_t output_capacity;
    unsigned int probe_countdown;
    struct timespec last_transfer;
    int producer_is_fast;
    int allow_fast_drop;
    unsigned int fast_streak;
    unsigned int normal_streak;
} plumos_pcm_t;

static int card_has_usb_id(int card)
{
    char path[64];
    snprintf(path, sizeof(path), "/proc/asound/card%d/usbid", card);
    return access(path, R_OK) == 0;
}

static int card_has_playback(int card)
{
    char path[64];
    snprintf(path, sizeof(path), "/dev/snd/pcmC%dD0p", card);
    return access(path, R_OK | W_OK) == 0;
}

static int find_usb_card(void)
{
    int card;
    for (card = 1; card <= MAX_CARD_INDEX; card++) {
        if (card_has_playback(card) && card_has_usb_id(card))
            return card;
    }
    return -1;
}

static void write_route_status(int card, int is_usb)
{
    const char *status = "/run/plumos/audio/output.status";
    char temporary[PATH_MAX];
    FILE *fp;

    snprintf(temporary, sizeof(temporary), "%s.tmp.%ld", status, (long)getpid());
    fp = fopen(temporary, "w");
    if (!fp)
        return;
    fprintf(fp,
            "mode=%s\n"
            "router=alsa_ioplug_hotplug\n"
            "card=%d\n"
            "physical_pcm=hw:%d,0\n"
            "pcm=plumos_output\n"
            "alsa_config_path=/run/plumos/audio/asound.conf\n",
            is_usb ? "usb_stereo" : "internal_mono", card, card);
    if (fclose(fp) == 0)
        rename(temporary, status);
    else
        unlink(temporary);
}

static int configure_physical(snd_pcm_t *pcm, const snd_pcm_ioplug_t *io)
{
    snd_pcm_hw_params_t *params;
    snd_pcm_sw_params_t *sw;
    snd_pcm_uframes_t period = io->period_size ? io->period_size : 768;
    snd_pcm_uframes_t buffer = io->buffer_size ? io->buffer_size : period * 4;
    unsigned int rate = io->rate;
    int direction = 0;
    int err;

    snd_pcm_hw_params_alloca(&params);
    if ((err = snd_pcm_hw_params_any(pcm, params)) < 0 ||
        (err = snd_pcm_hw_params_set_access(pcm, params,
                                             SND_PCM_ACCESS_RW_INTERLEAVED)) < 0 ||
        (err = snd_pcm_hw_params_set_format(pcm, params,
                                             SND_PCM_FORMAT_S16_LE)) < 0 ||
        (err = snd_pcm_hw_params_set_channels(pcm, params, 2)) < 0 ||
        (err = snd_pcm_hw_params_set_rate_near(pcm, params, &rate,
                                                &direction)) < 0 ||
        (err = snd_pcm_hw_params_set_period_size_near(pcm, params, &period,
                                                       &direction)) < 0 ||
        (err = snd_pcm_hw_params_set_buffer_size_near(pcm, params, &buffer)) < 0 ||
        (err = snd_pcm_hw_params(pcm, params)) < 0)
        return err;
    if (rate != io->rate)
        return -EINVAL;

    snd_pcm_sw_params_alloca(&sw);
    if ((err = snd_pcm_sw_params_current(pcm, sw)) < 0 ||
        (err = snd_pcm_sw_params_set_avail_min(pcm, sw, period)) < 0 ||
        (err = snd_pcm_sw_params_set_start_threshold(pcm, sw, period)) < 0 ||
        (err = snd_pcm_sw_params(pcm, sw)) < 0)
        return err;
    return snd_pcm_prepare(pcm);
}

static snd_pcm_t *open_physical(const snd_pcm_ioplug_t *io, int card)
{
    const plumos_pcm_t *owner = io->private_data;
    char name[32];
    snd_pcm_t *pcm = NULL;
    int mode = owner->allow_fast_drop ? SND_PCM_NONBLOCK : 0;
    int err;

    snprintf(name, sizeof(name), "hw:%d,0", card);
    err = snd_pcm_open(&pcm, name, SND_PCM_STREAM_PLAYBACK, mode);
    if (err < 0)
        return NULL;
    err = configure_physical(pcm, io);
    if (err < 0) {
        snd_pcm_close(pcm);
        return NULL;
    }
    return pcm;
}

static int switch_route(plumos_pcm_t *pcm, int force)
{
    snd_pcm_t *next;
    snd_pcm_t *old;
    int usb_card = find_usb_card();
    int target_card = usb_card >= 0 ? usb_card : INTERNAL_CARD;
    int target_is_usb = usb_card >= 0;

    if (!force && pcm->physical && pcm->physical_card == target_card)
        return 0;

    next = open_physical(&pcm->io, target_card);
    if (!next && target_is_usb) {
        target_card = INTERNAL_CARD;
        target_is_usb = 0;
        if (!force && pcm->physical && pcm->physical_card == target_card)
            return 0;
        next = open_physical(&pcm->io, target_card);
    }
    if (!next)
        return -ENODEV;

    old = pcm->physical;
    pcm->physical = next;
    pcm->physical_card = target_card;
    pcm->physical_is_usb = target_is_usb;
    pcm->probe_countdown = USB_PROBE_INTERVAL;
    if (old) {
        snd_pcm_drop(old);
        snd_pcm_close(old);
    }
    write_route_status(target_card, target_is_usb);
    fprintf(stderr, "plumos-hotplug: route=%s card=%d\n",
            target_is_usb ? "usb_stereo" : "internal_mono", target_card);
    return 0;
}

static int ensure_output_buffer(plumos_pcm_t *pcm, size_t frames)
{
    int16_t *resized;
    if (frames <= pcm->output_capacity)
        return 0;
    resized = realloc(pcm->output_buffer, frames * 2 * sizeof(*resized));
    if (!resized)
        return -ENOMEM;
    pcm->output_buffer = resized;
    pcm->output_capacity = frames;
    return 0;
}

static int16_t float_to_s16(float value)
{
    if (value >= 1.0f)
        return INT16_MAX;
    if (value <= -1.0f)
        return INT16_MIN;
    return (int16_t)(value * 32767.0f);
}

static snd_pcm_sframes_t write_physical(plumos_pcm_t *pcm,
                                        const int16_t *samples,
                                        snd_pcm_uframes_t frames)
{
    snd_pcm_uframes_t completed = 0;
    while (completed < frames) {
        snd_pcm_sframes_t written = snd_pcm_writei(
            pcm->physical, samples + completed * 2, frames - completed);
        if (written == -EPIPE || written == -ESTRPIPE) {
            int recovered = snd_pcm_recover(pcm->physical, (int)written, 1);
            if (recovered >= 0)
                continue;
            written = recovered;
        }
        if (written == -EAGAIN) {
            if (pcm->allow_fast_drop && pcm->producer_is_fast) {
                /* Fast-forward can produce audio faster than the device
                 * clock. Drop only those excess frames. */
                return (snd_pcm_sframes_t)frames;
            }
            snd_pcm_wait(pcm->physical, 20);
            continue;
        }
        if (written < 0)
            return written;
        if (written == 0)
            return -EIO;
        completed += (snd_pcm_uframes_t)written;
    }
    return (snd_pcm_sframes_t)completed;
}

static void update_producer_speed(plumos_pcm_t *pcm, snd_pcm_uframes_t frames)
{
    struct timespec now;
    int64_t delta_ns;
    int64_t expected_ns;

    if (clock_gettime(CLOCK_MONOTONIC, &now) < 0)
        return;
    if (pcm->last_transfer.tv_sec == 0 && pcm->last_transfer.tv_nsec == 0) {
        pcm->last_transfer = now;
        pcm->producer_is_fast = 0;
        return;
    }
    delta_ns = (int64_t)(now.tv_sec - pcm->last_transfer.tv_sec) * 1000000000LL +
               now.tv_nsec - pcm->last_transfer.tv_nsec;
    expected_ns = (int64_t)frames * 1000000000LL / pcm->io.rate;
    if (delta_ns > 0 && delta_ns * 2 < expected_ns) {
        pcm->fast_streak++;
        pcm->normal_streak = 0;
        if (pcm->fast_streak >= 4)
            pcm->producer_is_fast = 1;
    } else {
        pcm->normal_streak++;
        pcm->fast_streak = 0;
        if (pcm->normal_streak >= 2)
            pcm->producer_is_fast = 0;
    }
    pcm->last_transfer = now;
}

static snd_pcm_sframes_t plumos_transfer(snd_pcm_ioplug_t *io,
                                         const snd_pcm_channel_area_t *areas,
                                         snd_pcm_uframes_t offset,
                                         snd_pcm_uframes_t size)
{
    plumos_pcm_t *pcm = io->private_data;
    const void *input;
    const int16_t *output;
    snd_pcm_sframes_t result;
    snd_pcm_uframes_t frame;
    int err;

    if (!areas ||
        (io->format == SND_PCM_FORMAT_S16_LE && areas[0].step != 32) ||
        (io->format == SND_PCM_FORMAT_FLOAT_LE && areas[0].step != 64))
        return -EINVAL;
    input = (const unsigned char *)areas[0].addr + areas[0].first / 8 +
            offset * areas[0].step / 8;
    update_producer_speed(pcm, size);

    if (pcm->probe_countdown == 0) {
        err = switch_route(pcm, 0);
        if (err < 0)
            return err;
        pcm->probe_countdown = USB_PROBE_INTERVAL;
    } else {
        pcm->probe_countdown--;
    }

    if (!pcm->physical) {
        err = switch_route(pcm, 1);
        if (err < 0)
            return err;
    }

    output = input;
    if (io->format == SND_PCM_FORMAT_FLOAT_LE || !pcm->physical_is_usb) {
        err = ensure_output_buffer(pcm, size);
        if (err < 0)
            return err;
        for (frame = 0; frame < size; frame++) {
            int16_t left;
            int16_t right;
            if (io->format == SND_PCM_FORMAT_FLOAT_LE) {
                const float *float_input = input;
                left = float_to_s16(float_input[frame * 2]);
                right = float_to_s16(float_input[frame * 2 + 1]);
            } else {
                const int16_t *s16_input = input;
                left = s16_input[frame * 2];
                right = s16_input[frame * 2 + 1];
            }
            if (!pcm->physical_is_usb) {
                int16_t mono = (int16_t)(((int32_t)left + right) / 2);
                left = mono;
                right = mono;
            }
            pcm->output_buffer[frame * 2] = left;
            pcm->output_buffer[frame * 2 + 1] = right;
        }
        output = pcm->output_buffer;
    }

    result = write_physical(pcm, output, size);
    if (result < 0 && result != -EPIPE && result != -ESTRPIPE) {
        if (switch_route(pcm, 1) == 0) {
            if (!pcm->physical_is_usb) {
                err = ensure_output_buffer(pcm, size);
                if (err < 0)
                    return err;
                for (frame = 0; frame < size; frame++) {
                    int16_t left;
                    int16_t right;
                    if (io->format == SND_PCM_FORMAT_FLOAT_LE) {
                        const float *float_input = input;
                        left = float_to_s16(float_input[frame * 2]);
                        right = float_to_s16(float_input[frame * 2 + 1]);
                    } else {
                        const int16_t *s16_input = input;
                        left = s16_input[frame * 2];
                        right = s16_input[frame * 2 + 1];
                    }
                    int32_t mixed = (int32_t)left + right;
                    int16_t mono = (int16_t)(mixed / 2);
                    pcm->output_buffer[frame * 2] = mono;
                    pcm->output_buffer[frame * 2 + 1] = mono;
                }
                output = pcm->output_buffer;
            } else if (io->format == SND_PCM_FORMAT_FLOAT_LE) {
                err = ensure_output_buffer(pcm, size);
                if (err < 0)
                    return err;
                for (frame = 0; frame < size; frame++) {
                    const float *float_input = input;
                    pcm->output_buffer[frame * 2] =
                        float_to_s16(float_input[frame * 2]);
                    pcm->output_buffer[frame * 2 + 1] =
                        float_to_s16(float_input[frame * 2 + 1]);
                }
                output = pcm->output_buffer;
            } else {
                output = input;
            }
            result = write_physical(pcm, output, size);
        }
    }
    if (result > 0 && io->buffer_size) {
        pcm->hw_ptr = (pcm->hw_ptr + (snd_pcm_uframes_t)result) % io->buffer_size;
    }
    return result;
}

static int plumos_start(snd_pcm_ioplug_t *io)
{
    plumos_pcm_t *pcm = io->private_data;
    return pcm->physical ? 0 : switch_route(pcm, 1);
}

static int plumos_stop(snd_pcm_ioplug_t *io)
{
    plumos_pcm_t *pcm = io->private_data;
    if (pcm->physical)
        snd_pcm_drop(pcm->physical);
    return 0;
}

static snd_pcm_sframes_t plumos_pointer(snd_pcm_ioplug_t *io)
{
    plumos_pcm_t *pcm = io->private_data;
    return (snd_pcm_sframes_t)pcm->hw_ptr;
}

static int plumos_prepare(snd_pcm_ioplug_t *io)
{
    plumos_pcm_t *pcm = io->private_data;
    int err = switch_route(pcm, 0);
    if (err < 0)
        return err;
    pcm->hw_ptr = 0;
    return snd_pcm_prepare(pcm->physical);
}

static int plumos_drain(snd_pcm_ioplug_t *io)
{
    plumos_pcm_t *pcm = io->private_data;
    return pcm->physical ? snd_pcm_drain(pcm->physical) : 0;
}

static int plumos_delay(snd_pcm_ioplug_t *io, snd_pcm_sframes_t *delayp)
{
    plumos_pcm_t *pcm = io->private_data;
    if (!pcm->physical) {
        *delayp = 0;
        return 0;
    }
    return snd_pcm_delay(pcm->physical, delayp);
}

static int plumos_close(snd_pcm_ioplug_t *io)
{
    plumos_pcm_t *pcm = io->private_data;
    if (pcm->physical)
        snd_pcm_close(pcm->physical);
    close(pcm->poll_pipe[0]);
    close(pcm->poll_pipe[1]);
    free(pcm->output_buffer);
    free(pcm);
    return 0;
}

static const snd_pcm_ioplug_callback_t plumos_callbacks = {
    .start = plumos_start,
    .stop = plumos_stop,
    .pointer = plumos_pointer,
    .transfer = plumos_transfer,
    .close = plumos_close,
    .prepare = plumos_prepare,
    .drain = plumos_drain,
    .delay = plumos_delay,
};

static int set_constraints(snd_pcm_ioplug_t *io)
{
    static const unsigned int access[] = { SND_PCM_ACCESS_RW_INTERLEAVED };
    static const unsigned int format[] = {
        SND_PCM_FORMAT_S16_LE,
        SND_PCM_FORMAT_FLOAT_LE,
    };
    static const unsigned int channels[] = { 2 };
    int err;

    if ((err = snd_pcm_ioplug_set_param_list(io, SND_PCM_IOPLUG_HW_ACCESS,
                                              1, access)) < 0 ||
        (err = snd_pcm_ioplug_set_param_list(io, SND_PCM_IOPLUG_HW_FORMAT,
                                              2, format)) < 0 ||
        (err = snd_pcm_ioplug_set_param_list(io, SND_PCM_IOPLUG_HW_CHANNELS,
                                              1, channels)) < 0 ||
        (err = snd_pcm_ioplug_set_param_minmax(io, SND_PCM_IOPLUG_HW_RATE,
                                                8000, 192000)) < 0 ||
        (err = snd_pcm_ioplug_set_param_minmax(io,
                                                SND_PCM_IOPLUG_HW_PERIOD_BYTES,
                                                256, 65536)) < 0 ||
        (err = snd_pcm_ioplug_set_param_minmax(io,
                                                SND_PCM_IOPLUG_HW_BUFFER_BYTES,
                                                1024, 262144)) < 0 ||
        (err = snd_pcm_ioplug_set_param_minmax(io,
                                                SND_PCM_IOPLUG_HW_PERIODS,
                                                2, 8)) < 0)
        return err;
    return 0;
}

SND_PCM_PLUGIN_DEFINE_FUNC(plumos_hotplug)
{
    snd_config_iterator_t i, next;
    plumos_pcm_t *pcm;
    int err;

    if (stream != SND_PCM_STREAM_PLAYBACK)
        return -EINVAL;
    snd_config_for_each(i, next, conf) {
        snd_config_t *node = snd_config_iterator_entry(i);
        const char *id;
        if (snd_config_get_id(node, &id) < 0)
            continue;
        if (!strcmp(id, "comment") || !strcmp(id, "type") || !strcmp(id, "hint"))
            continue;
        SNDERR("Unknown field %s", id);
        return -EINVAL;
    }

    pcm = calloc(1, sizeof(*pcm));
    if (!pcm)
        return -ENOMEM;
    pcm->physical_card = -1;
    pcm->allow_fast_drop =
        getenv("PLUMOS_AUDIO_FAST_FORWARD_DROP") &&
        !strcmp(getenv("PLUMOS_AUDIO_FAST_FORWARD_DROP"), "1");
    pcm->poll_pipe[0] = -1;
    pcm->poll_pipe[1] = -1;
    if (pipe2(pcm->poll_pipe, O_NONBLOCK | O_CLOEXEC) < 0) {
        err = -errno;
        free(pcm);
        return err;
    }

    pcm->io.version = SND_PCM_IOPLUG_VERSION;
    pcm->io.name = "plumOS V90S hotplug audio";
    pcm->io.poll_fd = pcm->poll_pipe[1];
    pcm->io.poll_events = POLLOUT;
    pcm->io.mmap_rw = 0;
    pcm->io.callback = &plumos_callbacks;
    pcm->io.private_data = pcm;

    err = snd_pcm_ioplug_create(&pcm->io, name, stream, mode);
    if (err < 0)
        goto error;
    err = set_constraints(&pcm->io);
    if (err < 0) {
        snd_pcm_ioplug_delete(&pcm->io);
        return err;
    }
    *pcmp = pcm->io.pcm;
    return 0;

error:
    close(pcm->poll_pipe[0]);
    close(pcm->poll_pipe[1]);
    free(pcm);
    return err;
}

SND_PCM_PLUGIN_SYMBOL(plumos_hotplug);
