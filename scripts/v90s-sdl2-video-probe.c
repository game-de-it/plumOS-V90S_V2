#include <SDL.h>

#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;

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

    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_JOYSTICK | SDL_INIT_GAMECONTROLLER) != 0) {
        printf("sdl2-probe: SDL_Init failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    printf("sdl2-probe: current_video_driver=%s\n", SDL_GetCurrentVideoDriver());
    printf("sdl2-probe: joysticks=%d\n", SDL_NumJoysticks());
    for (int i = 0; i < SDL_NumJoysticks(); i++) {
        printf("sdl2-probe: joystick[%d]=%s\n", i, SDL_JoystickNameForIndex(i));
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
