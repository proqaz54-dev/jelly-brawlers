#include "game.h"
#include "renderer.h"

#include <android/log.h>
#include <jni.h>
#include <algorithm>
#include <cmath>

namespace {

Game g_game;
Renderer g_renderer;
int g_viewW = 0, g_viewH = 0;
const char* kTag = "jelly";

struct Ptr {
    int id = -1;
    bool active = false;
    int side = -1;
    int role = 0;  // 0 none, 1 joystick, 2 punch, 3 kick, 4 jump
    float u = 0.0f, v = 0.0f;
    float au = 0.0f, av = 0.0f;
};

Ptr g_ptrs[12];

// button offsets (normalized, within each half of the screen)
constexpr float kPunchDU = 0.44f;
constexpr float kJumpDU = 0.28f;
constexpr float kKickDU = 0.12f;
constexpr float kPunchDV = 0.78f;
constexpr float kJumpDV = 0.82f;
constexpr float kKickDV = 0.82f;
constexpr float kBtnHit = 0.5f;  // world-space hit radius

void worldHalf(float& halfW, float& halfH) {
    float aspect = g_viewH > 0 ? float(g_viewW) / float(g_viewH) : 1.6f;
    halfW = std::max(4.7f * aspect, Game::WORLD_HALF);
    halfH = 4.7f;
}

void normToWorld(float u, float v, float& wx, float& wy) {
    float halfW, halfH;
    worldHalf(halfW, halfH);
    wx = (u - 0.5f) * 2.0f * halfW;
    wy = (0.5f - v) * 2.0f * halfH;
}

void pollInputs() {
    for (int s = 0; s < 2; ++s) {
        g_game.input[s].joy = {0.0f, 0.0f};
        g_game.input[s].punch = false;
        g_game.input[s].kick = false;
        g_game.input[s].jump = false;
        g_game.joyActive[s] = false;
    }
    for (int i = 0; i < 12; ++i) {
        Ptr& p = g_ptrs[i];
        if (!p.active) continue;
        switch (p.role) {
            case 2:
                g_game.input[p.side].punch = true;
                break;
            case 3:
                g_game.input[p.side].kick = true;
                break;
            case 4:
                g_game.input[p.side].jump = true;
                break;
            case 1: {
                float bx, by, cx, cy;
                normToWorld(p.au, p.av, bx, by);
                normToWorld(p.u, p.v, cx, cy);
                Vec2 delta = {cx - bx, cy - by};
                if (delta.len() < 0.12f) {
                    g_game.input[p.side].joy = {0.0f, 0.0f};
                } else {
                    g_game.input[p.side].joy =
                        Vec2::clampMag(delta * (1.0f / 0.9f), 1.0f);
                }
                g_game.joyAnchor[p.side] = {p.au, p.av};
                g_game.joyActive[p.side] = true;
                break;
            }
            default:
                break;
        }
    }
}

void onTouchDown(int id, float u, float v) {
    Ptr* slot = nullptr;
    for (int i = 0; i < 12; ++i) {
        if (!g_ptrs[i].active) {
            slot = &g_ptrs[i];
            break;
        }
    }
    if (!slot) return;

    float wx, wy;
    normToWorld(u, v, wx, wy);

    slot->id = id;
    slot->active = true;
    slot->u = u;
    slot->v = v;
    slot->au = u;
    slot->av = v;

    if (g_game.state == GameState::Menu) {
        g_game.tapMenu({wx, wy});
        slot->role = 0;
        return;
    }

    int side = u < 0.5f ? 0 : 1;
    slot->side = side;

    float b = side == 0 ? 0.0f : 0.5f;
    // button world centers: punch, jump, kick
    float centers[3][2];
    normToWorld(b + kPunchDU, kPunchDV, centers[0][0], centers[0][1]);
    normToWorld(b + kJumpDU, kJumpDV, centers[1][0], centers[1][1]);
    normToWorld(b + kKickDU, kKickDV, centers[2][0], centers[2][1]);

    slot->role = 1;  // joystick by default
    for (int j = 0; j < 3; ++j) {
        float dx = wx - centers[j][0];
        float dy = wy - centers[j][1];
        if (dx * dx + dy * dy < kBtnHit * kBtnHit) {
            slot->role = 2 + j;
            break;
        }
    }
}

void onTouchMove(int id, float u, float v) {
    for (int i = 0; i < 12; ++i) {
        if (g_ptrs[i].active && g_ptrs[i].id == id) {
            g_ptrs[i].u = u;
            g_ptrs[i].v = v;
            return;
        }
    }
}

void onTouchUp(int id) {
    for (int i = 0; i < 12; ++i) {
        if (g_ptrs[i].active && g_ptrs[i].id == id) {
            g_ptrs[i].active = false;
            return;
        }
    }
}

}  // namespace

extern "C" {

JNIEXPORT void JNICALL Java_com_jellybrawlers_app_MainActivity_nativeInit(
    JNIEnv*, jobject) {
    __android_log_print(ANDROID_LOG_INFO, kTag, "native init");
    if (g_renderer.init()) {
        __android_log_print(ANDROID_LOG_INFO, kTag, "renderer ready");
    } else {
        __android_log_print(ANDROID_LOG_ERROR, kTag, "renderer init failed");
    }
}

JNIEXPORT void JNICALL Java_com_jellybrawlers_app_MainActivity_nativeResize(
    JNIEnv*, jobject, jint w, jint h) {
    g_viewW = w;
    g_viewH = h;
}

JNIEXPORT void JNICALL Java_com_jellybrawlers_app_MainActivity_nativeFrame(
    JNIEnv*, jobject, jfloat dt) {
    pollInputs();
    g_game.step(dt);
    g_renderer.render(g_game, g_viewW, g_viewH);
}

JNIEXPORT void JNICALL Java_com_jellybrawlers_app_MainActivity_nativeTouch(
    JNIEnv*, jobject, jint action, jint id, jfloat u, jfloat v) {
    switch (action) {
        case 0:
            onTouchDown(id, u, v);
            break;
        case 1:
            onTouchUp(id);
            break;
        case 2:
            onTouchMove(id, u, v);
            break;
        default:
            break;
    }
}

}  // extern "C"