#include <SDL.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int parse_input_seconds(int argc, char **argv)
{
    if (argc == 3 && strcmp(argv[1], "--input-only") == 0) {
        char *end = NULL;
        long value = strtol(argv[2], &end, 10);
        if (end && *end == '\0' && value > 0 && value <= 300)
            return (int)value;
    }
    return 0;
}

static int run_input_probe(int seconds)
{
    SDL_Joystick *joystick = NULL;
    SDL_JoystickGUID guid;
    char guid_text[64];
    Uint32 deadline;

    if (SDL_NumJoysticks() < 1) {
        printf("sdl2-probe: no joystick available\n");
        return 4;
    }

    joystick = SDL_JoystickOpen(0);
    if (!joystick) {
        printf("sdl2-probe: SDL_JoystickOpen failed: %s\n", SDL_GetError());
        return 5;
    }

    guid = SDL_JoystickGetGUID(joystick);
    SDL_JoystickGetGUIDString(guid, guid_text, sizeof(guid_text));
    printf("sdl2-probe: input name=%s guid=%s axes=%d buttons=%d hats=%d balls=%d\n",
           SDL_JoystickName(joystick), guid_text,
           SDL_JoystickNumAxes(joystick), SDL_JoystickNumButtons(joystick),
           SDL_JoystickNumHats(joystick), SDL_JoystickNumBalls(joystick));
    printf("sdl2-probe: input capture=%d seconds\n", seconds);
    fflush(stdout);

    deadline = SDL_GetTicks() + (Uint32)seconds * 1000;
    while ((Sint32)(deadline - SDL_GetTicks()) > 0) {
        SDL_Event event;
        if (!SDL_WaitEventTimeout(&event, 100))
            continue;
        switch (event.type) {
        case SDL_JOYAXISMOTION:
            printf("sdl2-probe: axis index=%u value=%d\n",
                   event.jaxis.axis, event.jaxis.value);
            break;
        case SDL_JOYHATMOTION:
            printf("sdl2-probe: hat index=%u value=%u\n",
                   event.jhat.hat, event.jhat.value);
            break;
        case SDL_JOYBUTTONDOWN:
        case SDL_JOYBUTTONUP:
            printf("sdl2-probe: button index=%u pressed=%u\n",
                   event.jbutton.button,
                   event.type == SDL_JOYBUTTONDOWN ? 1U : 0U);
            break;
        default:
            continue;
        }
        fflush(stdout);
    }

    SDL_JoystickClose(joystick);
    printf("sdl2-probe: input capture complete\n");
    return 0;
}

int main(int argc, char **argv)
{
    int input_seconds = parse_input_seconds(argc, argv);

    SDL_version compiled;
    SDL_version linked;
    SDL_VERSION(&compiled);
    SDL_GetVersion(&linked);

    printf("sdl2-probe: compiled=%u.%u.%u linked=%u.%u.%u\n",
           compiled.major, compiled.minor, compiled.patch,
           linked.major, linked.minor, linked.patch);
    printf("sdl2-probe: SDL_VIDEODRIVER=%s\n",
           getenv("SDL_VIDEODRIVER") ? getenv("SDL_VIDEODRIVER") : "(unset)");

    int drivers = SDL_GetNumVideoDrivers();
    printf("sdl2-probe: video_driver_count=%d\n", drivers);
    for (int i = 0; i < drivers; i++) {
        printf("sdl2-probe: video_driver[%d]=%s\n", i, SDL_GetVideoDriver(i));
    }

    SDL_SetHint(SDL_HINT_RENDER_DRIVER, "opengles2");

    if (SDL_Init((input_seconds ? 0 : SDL_INIT_VIDEO) |
                 SDL_INIT_JOYSTICK | SDL_INIT_GAMECONTROLLER) != 0) {
        printf("sdl2-probe: SDL_Init failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    printf("sdl2-probe: current_video_driver=%s\n", SDL_GetCurrentVideoDriver());
    printf("sdl2-probe: joysticks=%d\n", SDL_NumJoysticks());
    for (int i = 0; i < SDL_NumJoysticks(); i++) {
        printf("sdl2-probe: joystick[%d]=%s\n", i, SDL_JoystickNameForIndex(i));
    }

    if (input_seconds) {
        int rc = run_input_probe(input_seconds);
        SDL_Quit();
        return rc;
    }

    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);

    SDL_Window *window = SDL_CreateWindow(
        "plumOS V90S SDL2 probe",
        SDL_WINDOWPOS_UNDEFINED,
        SDL_WINDOWPOS_UNDEFINED,
        640,
        480,
        SDL_WINDOW_OPENGL | SDL_WINDOW_FULLSCREEN);
    if (!window) {
        printf("sdl2-probe: SDL_CreateWindow failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 2;
    }
    printf("sdl2-probe: SDL_CreateWindow ok\n");

    SDL_GLContext context = SDL_GL_CreateContext(window);
    if (!context) {
        printf("sdl2-probe: SDL_GL_CreateContext failed: %s\n", SDL_GetError());
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 3;
    }
    printf("sdl2-probe: SDL_GL_CreateContext ok\n");

    SDL_GL_SwapWindow(window);
    SDL_Delay(750);

    SDL_GL_DeleteContext(context);
    SDL_DestroyWindow(window);
    SDL_Quit();
    printf("sdl2-probe: ok\n");
    return 0;
}
