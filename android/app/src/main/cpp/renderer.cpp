#include "renderer.h"

#include <GLES2/gl2.h>
#include <android/log.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <vector>

namespace {

constexpr int FONT_W = 3;
constexpr int FONT_H = 5;

struct Glyph {
    char c;
    uint8_t r[FONT_H];
};

const Glyph GLYPHS[] = {
    {'A', {7, 5, 7, 5, 5}}, {'B', {6, 5, 6, 5, 6}}, {'C', {7, 4, 4, 4, 7}},
    {'D', {6, 5, 5, 5, 6}}, {'E', {7, 4, 6, 4, 7}}, {'F', {7, 4, 6, 4, 4}},
    {'G', {7, 4, 5, 5, 7}}, {'H', {5, 5, 7, 5, 5}}, {'I', {7, 2, 2, 2, 7}},
    {'J', {7, 1, 1, 5, 6}}, {'K', {5, 5, 6, 5, 5}}, {'L', {4, 4, 4, 4, 7}},
    {'M', {5, 7, 7, 5, 5}}, {'N', {7, 5, 5, 5, 5}}, {'O', {7, 5, 5, 5, 7}},
    {'P', {7, 5, 7, 4, 4}}, {'Q', {7, 5, 5, 7, 1}}, {'R', {7, 5, 7, 6, 5}},
    {'S', {7, 4, 7, 1, 7}}, {'T', {7, 2, 2, 2, 2}}, {'U', {5, 5, 5, 5, 7}},
    {'V', {5, 5, 5, 5, 2}}, {'W', {5, 5, 7, 7, 5}}, {'X', {5, 5, 2, 5, 5}},
    {'Y', {5, 5, 2, 2, 2}}, {'Z', {7, 1, 2, 4, 7}}, {'0', {7, 5, 5, 5, 7}},
    {'1', {2, 6, 2, 2, 7}}, {'2', {7, 1, 7, 4, 7}}, {'3', {7, 1, 7, 1, 7}},
    {'4', {5, 5, 7, 1, 1}}, {'5', {7, 4, 7, 1, 7}}, {'6', {7, 4, 7, 5, 7}},
    {'7', {7, 1, 2, 2, 2}}, {'8', {7, 5, 7, 5, 7}}, {'9', {7, 5, 7, 1, 7}},
    {'!', {2, 2, 2, 0, 2}}, {'.', {0, 0, 0, 0, 2}}, {'-', {0, 0, 7, 0, 0}},
    {':', {0, 2, 0, 2, 0}},
};

const Glyph* findGlyph(char c) {
    if (c >= 'a' && c <= 'z') c = 'A' + (c - 'a');
    for (const Glyph& g : GLYPHS) {
        if (g.c == c) return &g;
    }
    return nullptr;
}

struct Rect {
    float x0, y0, x1, y1;
    uint32_t color;
};

std::vector<Rect> g_rects;
float g_proj[16];

constexpr uint32_t ARGB(uint32_t a, uint32_t r, uint32_t g, uint32_t b) {
    return (a << 24) | (r << 16) | (g << 8) | b;
}

void color4(uint32_t c, float* out) {
    out[0] = float((c >> 24) & 0xFF) / 255.0f;
    out[1] = float((c >> 16) & 0xFF) / 255.0f;
    out[2] = float((c >> 8) & 0xFF) / 255.0f;
    out[3] = float(c & 0xFF) / 255.0f;
}

void mat4Ortho(float* m, float l, float r, float b, float t) {
    memset(m, 0, sizeof(float) * 16);
    m[0] = 2.0f / (r - l);
    m[5] = 2.0f / (t - b);
    m[10] = -1.0f;
    m[12] = -(r + l) / (r - l);
    m[13] = -(t + b) / (t - b);
    m[15] = 1.0f;
}

void mat4Identity(float* m) {
    memset(m, 0, sizeof(float) * 16);
    m[0] = m[5] = m[10] = m[15] = 1.0f;
}

void mat4Mul(float* out, const float* a, const float* b) {
    float r[16];
    for (int col = 0; col < 4; ++col) {
        for (int row = 0; row < 4; ++row) {
            r[col * 4 + row] = a[col * 4 + 0] * b[0 * 4 + row] +
                               a[col * 4 + 1] * b[1 * 4 + row] +
                               a[col * 4 + 2] * b[2 * 4 + row] +
                               a[col * 4 + 3] * b[3 * 4 + row];
        }
    }
    memcpy(out, r, sizeof(r));
}

void mat4Translate(float* m, float x, float y) {
    m[12] += m[0] * x + m[4] * y;
    m[13] += m[1] * x + m[5] * y;
    m[14] += m[2] * x + m[6] * y;
    m[15] += m[3] * x + m[7] * y;
}

bool compileShader(unsigned int type, const char* src, unsigned int& out) {
    unsigned int sh = glCreateShader(type);
    glShaderSource(sh, 1, &src, nullptr);
    glCompileShader(sh);
    int ok = 0;
    glGetShaderiv(sh, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[512];
        glGetShaderInfoLog(sh, 512, nullptr, log);
        __android_log_print(ANDROID_LOG_ERROR, "jelly", "shader: %s", log);
        glDeleteShader(sh);
        return false;
    }
    out = sh;
    return true;
}

float lerp(float a, float b, float t) { return a + (b - a) * t; }

uint32_t lerpColor(uint32_t c1, uint32_t c2, float t) {
    float a[4], b[4], o[4];
    color4(c1, a);
    color4(c2, b);
    for (int i = 0; i < 4; ++i) o[i] = lerp(a[i], b[i], t);
    uint32_t c = 0;
    for (int i = 0; i < 4; ++i) c |= (uint32_t(o[i] * 255.0f) & 0xFF) << (24 - i * 8);
    return c;
}

}  // namespace

bool Renderer::init() {
    g_rects.reserve(2048);

    const char* vertCircle =
        "attribute vec2 aPos; uniform mat4 uMvp;\n"
        "void main(){ gl_Position = uMvp * vec4(aPos, 0.0, 1.0); }\n";
    const char* fragCircle =
        "precision mediump float; uniform vec4 uColor;\n"
        "void main(){ gl_FragColor = uColor; }\n";

    const char* vertRect =
        "attribute vec2 aPos; attribute vec4 aColor; varying vec4 vColor;\n"
        "uniform mat4 uMvp;\n"
        "void main(){ vColor = aColor; gl_Position = uMvp * vec4(aPos, 0.0, 1.0); }\n";
    const char* fragRect =
        "precision mediump float; varying vec4 vColor;\n"
        "void main(){ gl_FragColor = vColor; }\n";

    unsigned int vs, fs;
    if (!compileShader(GL_VERTEX_SHADER, vertCircle, vs)) return false;
    if (!compileShader(GL_FRAGMENT_SHADER, fragCircle, fs)) return false;
    progCircle_ = glCreateProgram();
    glAttachShader(progCircle_, vs);
    glAttachShader(progCircle_, fs);
    glBindAttribLocation(progCircle_, 0, "aPos");
    glLinkProgram(progCircle_);
    int ok = 0;
    glGetProgramiv(progCircle_, GL_LINK_STATUS, &ok);
    if (!ok) return false;
    glDeleteShader(vs);
    glDeleteShader(fs);

    if (!compileShader(GL_VERTEX_SHADER, vertRect, vs)) return false;
    if (!compileShader(GL_FRAGMENT_SHADER, fragRect, fs)) return false;
    progRect_ = glCreateProgram();
    glAttachShader(progRect_, vs);
    glAttachShader(progRect_, fs);
    glBindAttribLocation(progRect_, 0, "aPos");
    glBindAttribLocation(progRect_, 1, "aColor");
    glLinkProgram(progRect_);
    glGetProgramiv(progRect_, GL_LINK_STATUS, &ok);
    if (!ok) return false;
    glDeleteShader(vs);
    glDeleteShader(fs);

    uMvpCircle_ = glGetUniformLocation(progCircle_, "uMvp");
    uColorCircle_ = glGetUniformLocation(progCircle_, "uColor");
    uMvpRect_ = glGetUniformLocation(progRect_, "uMvp");

    const int SEG = 32;
    std::vector<float> circle;
    for (int i = 0; i <= SEG; ++i) {
        float a = float(i) / float(SEG) * 6.2831853f;
        circle.push_back(std::cos(a));
        circle.push_back(std::sin(a));
    }
    glGenBuffers(1, &vboCircle_);
    glBindBuffer(GL_ARRAY_BUFFER, vboCircle_);
    glBufferData(GL_ARRAY_BUFFER, circle.size() * sizeof(float), circle.data(),
                 GL_STATIC_DRAW);

    glGenBuffers(1, &vboRect_);
    glBindBuffer(GL_ARRAY_BUFFER, vboRect_);
    glBufferData(GL_ARRAY_BUFFER, 0, nullptr, GL_DYNAMIC_DRAW);

    glDisable(GL_DEPTH_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glClearColor(0.05f, 0.03f, 0.12f, 1.0f);
    return true;
}

void Renderer::drawCircle(float x, float y, float r, uint32_t color, float sx,
                          float sy, float rot) {
    float model[16], tmp[16], mvp[16];
    mat4Identity(model);
    mat4Translate(model, x, y);
    mat4Identity(tmp);
    tmp[0] = r * sx;
    tmp[5] = r * sy;
    mat4Mul(model, model, tmp);
    if (rot != 0.0f) {
        float c = std::cos(rot), s = std::sin(rot);
        mat4Identity(tmp);
        tmp[0] = c;
        tmp[1] = s;
        tmp[4] = -s;
        tmp[5] = c;
        mat4Mul(model, model, tmp);
    }
    mat4Mul(mvp, g_proj, model);

    float col[4];
    color4(color, col);
    glUseProgram(progCircle_);
    glUniformMatrix4fv(uMvpCircle_, 1, GL_FALSE, mvp);
    glUniform4fv(uColorCircle_, 1, col);
    glBindBuffer(GL_ARRAY_BUFFER, vboCircle_);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0);
    glDrawArrays(GL_TRIANGLE_FAN, 0, 33);
    glDisableVertexAttribArray(0);
}

void Renderer::drawRect(float x0, float y0, float x1, float y1,
                        uint32_t color) {
    if (g_rects.size() >= 4096) flushRects();
    g_rects.push_back({x0, y0, x1, y1, color});
}

void Renderer::flushRects() {
    if (g_rects.empty()) return;
    const size_t n = g_rects.size();
    std::vector<float> v;
    v.reserve(n * 6 * 6);
    for (const Rect& r : g_rects) {
        float cc[4];
        color4(r.color, cc);
        float quad[6][2] = {{r.x0, r.y0}, {r.x1, r.y0}, {r.x0, r.y1},
                            {r.x1, r.y0}, {r.x1, r.y1}, {r.x0, r.y1}};
        for (auto& q : quad) {
            v.push_back(q[0]);
            v.push_back(q[1]);
            v.push_back(cc[0]);
            v.push_back(cc[1]);
            v.push_back(cc[2]);
            v.push_back(cc[3]);
        }
    }
    g_rects.clear();

    glUseProgram(progRect_);
    glUniformMatrix4fv(uMvpRect_, 1, GL_FALSE, g_proj);
    glBindBuffer(GL_ARRAY_BUFFER, vboRect_);
    glBufferData(GL_ARRAY_BUFFER, v.size() * sizeof(float), v.data(),
                 GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 24, 0);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, 24,
                          reinterpret_cast<void*>(8));
    glDrawArrays(GL_TRIANGLES, 0, GLsizei(n * 6));
    glDisableVertexAttribArray(1);
    glDisableVertexAttribArray(0);
}

void Renderer::drawText(const char* s, float x, float y, float scale,
                        uint32_t color) {
    float cx = x;
    for (const char* p = s; *p; ++p) {
        char c = *p;
        if (c == ' ') {
            cx += scale * (FONT_W + 1);
            continue;
        }
        const Glyph* g = findGlyph(c);
        if (!g) {
            cx += scale * (FONT_W + 1);
            continue;
        }
        for (int row = 0; row < FONT_H; ++row) {
            for (int col = 0; col < FONT_W; ++col) {
                if (!((g->r[row] >> (FONT_W - 1 - col)) & 1u)) continue;
                drawRect(cx + col * scale, y + row * scale,
                         cx + (col + 1) * scale, y + (row + 1) * scale, color);
            }
        }
        cx += scale * (FONT_W + 1);
    }
}

void Renderer::drawTextOutlined(const char* s, float x, float y, float scale,
                                uint32_t color, uint32_t outline) {
    drawText(s, x - scale * 0.3f, y - scale * 0.3f, scale, outline);
    drawText(s, x + scale * 0.3f, y - scale * 0.3f, scale, outline);
    drawText(s, x - scale * 0.3f, y + scale * 0.3f, scale, outline);
    drawText(s, x + scale * 0.3f, y + scale * 0.3f, scale, outline);
    drawText(s, x, y, scale, color);
}

// draws text horizontally centered around cx
void Renderer::drawTextCentered(const char* s, float cx, float y, float scale,
                                uint32_t color, uint32_t outline,
                                bool outlined) {
    float w = (float(std::strlen(s)) * (FONT_W + 1) - 1.0f) * scale;
    float x = cx - w * 0.5f;
    if (outlined)
        drawTextOutlined(s, x, y, scale, color, outline);
    else
        drawText(s, x, y, scale, color);
}

void Renderer::drawBackground(const Game& g, float halfW, float halfH) {
    (void)g;
    uint32_t top = ARGB(255, 38, 20, 74);
    uint32_t mid = ARGB(255, 24, 13, 52);
    uint32_t bot = ARGB(255, 12, 6, 28);
    const int BANDS = 10;
    for (int i = 0; i < BANDS; ++i) {
        float t0 = float(i) / BANDS;
        float t1 = float(i + 1) / BANDS;
        float midT = (t0 + t1) * 0.5f;
        uint32_t col = midT < 0.5f ? lerpColor(top, mid, midT * 2.0f)
                                   : lerpColor(mid, bot, (midT - 0.5f) * 2.0f);
        drawRect(-halfW - 1.0f, -halfH - 1.0f + t0 * (halfH * 2.0f + 2.0f),
                 halfW + 1.0f, -halfH - 1.0f + t1 * (halfH * 2.0f + 2.0f), col);
    }
    // faint stars
    for (int i = 0; i < 24; ++i) {
        float sx = fmodf(float(i) * 37.7f, 14.0f) - 7.0f;
        float sy = fmodf(float(i) * 13.3f + 5.0f, 6.0f) + 0.5f;
        float tw = 0.5f + 0.5f * std::sin(g.time * 2.0f + i * 1.7f);
        drawCircle(sx, sy, 0.035f + 0.03f * tw, ARGB(uint32_t(120 * tw), 255, 255, 255));
    }
}

void Renderer::drawArena(const Game& g, float time) {
    const float W = Game::WORLD_HALF;
    const float G = Game::GAP;
    (void)time;

    // floor blocks
    uint32_t floorC = ARGB(255, 70, 78, 110);
    uint32_t floorEdge = ARGB(255, 96, 106, 148);
    uint32_t floorDark = ARGB(255, 52, 58, 84);
    drawRect(-W, 0.0f, -G, -1.5f, floorC);
    drawRect(G, 0.0f, W, -1.5f, floorC);
    drawRect(-W, 0.0f, -G, -0.14f, floorEdge);
    drawRect(G, 0.0f, W, -0.14f, floorEdge);
    drawRect(-W, -1.5f, -G, -1.62f, floorDark);
    drawRect(G, -1.5f, W, -1.62f, floorDark);

    // gap inner walls
    drawRect(-G - 0.18f, 0.0f, -G, -1.5f, floorDark);
    drawRect(G, 0.0f, G + 0.18f, -1.5f, floorDark);

    // side walls
    drawRect(-W - 0.45f, 0.0f, -W, Game::WALL_H, ARGB(255, 44, 49, 78));
    drawRect(W, 0.0f, W + 0.45f, Game::WALL_H, ARGB(255, 44, 49, 78));
    drawRect(-W - 0.45f, Game::WALL_H - 0.3f, W + 0.45f, Game::WALL_H,
             ARGB(255, 58, 64, 100));
    // wall padding dots
    for (int i = 0; i < 6; ++i) {
        float y = 0.7f + i * 1.0f;
        drawCircle(-W - 0.22f, y, 0.12f, ARGB(255, 70, 78, 118));
        drawCircle(W + 0.22f, y, 0.12f, ARGB(255, 70, 78, 118));
    }

    // lava below the gap
    float pulse = 0.5f + 0.5f * std::sin(g.time * 6.0f);
    uint32_t lava = lerpColor(ARGB(255, 255, 90, 30), ARGB(255, 255, 200, 80), pulse);
    drawRect(-G + 0.22f, -2.35f, G - 0.22f, -1.8f, lava);
    drawRect(-G + 0.22f, -1.8f, G - 0.22f, -1.35f, ARGB(110, 255, 120, 40));
    drawRect(-G + 0.22f, -2.5f, G - 0.22f, -2.35f, ARGB(160, 255, 70, 20));
}

void Renderer::drawCharacter(const Game& g, const Character& ch, float time) {
    (void)g;
    (void)time;
    bool sunk = ch.p[PART_FOOT_L].y < -2.3f && ch.p[PART_FOOT_R].y < -2.3f &&
                ch.p[PART_TORSO].y < -2.2f;
    if (sunk) return;

    Vec2 torso = ch.p[PART_TORSO];
    Vec2 head = ch.p[PART_HEAD];
    Vec2 d = head - torso;
    float len = d.len();
    float ang = std::atan2(d.y, d.x);

    auto limb = [&](int idx, float r) {
        drawCircle(ch.p[idx].x, ch.p[idx].y, r * 1.22f, ch.colorDark);
        drawCircle(ch.p[idx].x, ch.p[idx].y, r, ch.color);
        drawCircle(ch.p[idx].x - r * 0.25f, ch.p[idx].y + r * 0.3f, r * 0.45f,
                   ARGB(200, 255, 255, 255));
    };

    // feet behind
    limb(PART_FOOT_L, 0.22f);
    limb(PART_FOOT_R, 0.22f);

    // torso (jelly capsule along head->torso axis)
    float tHalf = len * 0.5f + 0.2f;
    Vec2 mid = torso + d * 0.5f;
    drawCircle(mid.x, mid.y, 0.36f, ch.colorDark, tHalf / 0.36f, 1.06f, ang);
    drawCircle(mid.x, mid.y, 0.36f, ch.color, tHalf / 0.36f, 0.94f, ang);
    Vec2 up = d.perp().normalized();
    drawCircle(mid.x + up.x * 0.12f, mid.y + up.y * 0.12f, 0.36f * 0.5f,
               ARGB(170, 255, 255, 255), 0.9f, 0.6f, ang);

    // head with jelly squash
    Vec2 hv = ch.p[PART_HEAD] - ch.p0[PART_HEAD];
    float sp = std::min(0.22f, hv.len() * 0.06f);
    float sx = 1.0f - sp, sy = 1.0f + sp * 0.7f;
    drawCircle(head.x, head.y, 0.36f, ch.colorDark, sx * 1.1f, sy * 1.1f);
    drawCircle(head.x, head.y, 0.36f, ch.color, sx, sy);
    drawCircle(head.x - 0.09f, head.y + 0.11f, 0.2f, ARGB(150, 255, 255, 255),
               0.85f, 0.6f);

    // face
    float f = float(ch.face);
    float ex = head.x + f * 0.13f;
    drawCircle(ex, head.y + 0.11f, 0.1f, ARGB(255, 255, 255, 255));
    drawCircle(ex, head.y - 0.11f, 0.1f, ARGB(255, 255, 255, 255));
    drawCircle(ex + f * 0.035f, head.y + 0.11f, 0.05f, ARGB(255, 30, 25, 35));
    drawCircle(ex + f * 0.035f, head.y - 0.11f, 0.05f, ARGB(255, 30, 25, 35));
    drawCircle(head.x + f * 0.05f, head.y - 0.18f, 0.04f, ARGB(255, 40, 30, 45));

    // hands in front
    limb(PART_HAND_L, 0.2f);
    limb(PART_HAND_R, 0.2f);
}

void Renderer::drawParticles(const Game& g) {
    for (const Particle& p : g.particles) {
        float a = std::clamp(p.life / p.maxLife, 0.0f, 1.0f);
        uint32_t col = (p.color & 0x00FFFFFFu) | (uint32_t(255.0f * a) << 24);
        drawCircle(p.pos.x, p.pos.y, p.r, col);
    }
}

void Renderer::drawHud(const Game& g, float halfW, float halfH) {
    if (g.state == GameState::Menu) return;
    float topY = halfH - 0.72f;
    for (int i = 0; i < 2; ++i) {
        const Character& ch = g.c[i];
        float dir = i == 0 ? 1.0f : -1.0f;
        float baseX = i == 0 ? -halfW + 0.9f : halfW - 0.9f;
        drawTextOutlined(i == 0 ? "P1" : "P2", baseX - dir * 0.55f, topY + 0.02f,
                         0.17f, ch.colorLight, ARGB(255, 10, 8, 24));
        for (int s = 0; s < 3; ++s) {
            float px = baseX + dir * s * 0.52f;
            drawCircle(px, topY - 0.2f, 0.16f, ch.colorDark);
            if (s < g.score[i]) {
                drawCircle(px, topY - 0.2f, 0.14f, ch.color);
                drawCircle(px - 0.03f, topY - 0.16f, 0.06f,
                           ARGB(200, 255, 255, 255));
            } else {
                drawCircle(px, topY - 0.2f, 0.14f, ARGB(255, 16, 12, 34));
            }
        }
    }
    // mode label
    const char* modeTxt = g.mode == 0 ? "1P VS BOT" : "2 PLAYERS";
    drawTextCentered(modeTxt, 0.0f, topY + 0.02f, 0.12f,
                     ARGB(255, 180, 188, 230), ARGB(255, 10, 8, 24), true);
}

void Renderer::drawTouchUi(const Game& g, float halfW, float halfH) {
    if (g.state == GameState::Menu) return;
    auto normToWorld = [&](float u, float v) {
        return Vec2((u - 0.5f) * 2.0f * halfW, (0.5f - v) * 2.0f * halfH);
    };

    for (int i = 0; i < 2; ++i) {
        float bx = i == 0 ? 0.0f : 0.5f;
        // joystick
        if (g.joyActive[i]) {
            Vec2 base = normToWorld(g.joyAnchor[i].x, g.joyAnchor[i].y);
            drawCircle(base.x, base.y, 0.5f, ARGB(80, 255, 255, 255));
            Vec2 kn = base + g.input[i].joy * 0.3f;
            drawCircle(kn.x, kn.y, 0.26f, ARGB(140, 255, 255, 255));
        }
        // buttons
        auto btn = [&](float du, float dv, float r, uint32_t col, bool held,
                       const char* label) {
            Vec2 p = normToWorld(bx + du, dv);
            float sc = held ? 1.14f : 1.0f;
            drawCircle(p.x, p.y, r * sc + 0.06f, ARGB(255, 20, 16, 40));
            drawCircle(p.x, p.y, r * sc, col);
            if (held) drawCircle(p.x, p.y, r * sc + 0.04f, ARGB(255, 255, 255, 255));
            drawTextCentered(label, p.x, p.y - 0.13f, 0.055f,
                             ARGB(255, 25, 18, 30), 0, false);
        };
        btn(0.28f, 0.82f, 0.4f, ARGB(235, 255, 210, 90), g.input[i].jump, "JMP");
        btn(0.44f, 0.78f, 0.46f, ARGB(235, 255, 110, 80), g.input[i].punch,
            "PNCH");
        btn(0.12f, 0.82f, 0.38f, ARGB(235, 90, 170, 255), g.input[i].kick, "KIK");
    }
}

void Renderer::drawMenu(const Game& g, float halfW, float halfH) {
    if (g.state != GameState::Menu) return;
    (void)halfW;
    (void)halfH;
    drawTextCentered("JELLY BRAWLERS", 0.0f, 2.55f, 0.19f,
                     ARGB(255, 255, 235, 160), ARGB(255, 90, 30, 120), true);
    drawTextCentered("RAGDOLL ARENA BRAWLER", 0.0f, 1.72f, 0.1f,
                     ARGB(255, 170, 178, 225), 0, false);

    // button 0: vs bot
    Vec2 b0(-2.4f, -1.2f);
    drawCircle(b0.x, b0.y, 0.95f, ARGB(255, 20, 40, 80));
    drawCircle(b0.x, b0.y, 0.9f, ARGB(255, 80, 170, 255));
    drawCircle(b0.x - 0.2f, b0.y + 0.25f, 0.35f, ARGB(150, 255, 255, 255));
    drawTextCentered("1P VS BOT", b0.x, b0.y - 0.16f, 0.12f, ARGB(255, 10, 20, 40),
                     ARGB(255, 200, 230, 255), true);

    // button 1: 2 players
    Vec2 b1(2.4f, -1.2f);
    drawCircle(b1.x, b1.y, 0.95f, ARGB(255, 70, 20, 12));
    drawCircle(b1.x, b1.y, 0.9f, ARGB(255, 255, 110, 80));
    drawCircle(b1.x - 0.2f, b1.y + 0.25f, 0.35f, ARGB(150, 255, 255, 255));
    drawTextCentered("2 PLAYERS", b1.x, b1.y - 0.16f, 0.12f, ARGB(255, 40, 8, 4),
                     ARGB(255, 255, 210, 190), true);

    drawTextCentered("TAP TO START - INSPIRED BY GANG BEASTS", 0.0f, -3.3f, 0.085f,
                     ARGB(255, 130, 140, 180), 0, false);
}

void Renderer::render(const Game& g, int viewW, int viewH) {
    if (viewW <= 0 || viewH <= 0) return;
    glViewport(0, 0, viewW, viewH);
    float aspect = float(viewW) / float(viewH);
    float halfW = std::max(4.7f * aspect, Game::WORLD_HALF);
    float halfH = 4.7f;

    float shx = 0.0f, shy = 0.0f;
    if (g.shake > 0.0f) {
        shx = (std::rand() % 1000 - 500) / 500.0f * 0.09f * g.shake;
        shy = (std::rand() % 1000 - 500) / 500.0f * 0.09f * g.shake;
    }
    mat4Ortho(g_proj, -halfW + shx, halfW + shx, -halfH + shy, halfH + shy);

    glClear(GL_COLOR_BUFFER_BIT);

    drawBackground(g, halfW, halfH);
    drawArena(g, g.time);
    drawParticles(g);

    if (g.state != GameState::Menu) {
        drawCharacter(g, g.c[0], g.time);
        drawCharacter(g, g.c[1], g.time);
    }

    if (g.state == GameState::Menu) {
        drawMenu(g, halfW, halfH);
    } else {
        drawTouchUi(g, halfW, halfH);
        drawHud(g, halfW, halfH);

        if (g.state == GameState::Countdown) {
            int n = int(std::ceil(g.countdownT / 0.533f));
            if (n >= 1 && n <= 3) {
                char buf[2] = {char('0' + n), 0};
                drawTextCentered(buf, 0.0f, 2.0f, 0.5f,
                                 ARGB(255, 255, 255, 255), ARGB(255, 60, 20, 90),
                                 true);
            }
        } else if (g.state == GameState::RoundOver) {
            if (g.c[0].fell && g.c[1].fell) {
                drawTextCentered("DOUBLE KO!", 0.0f, 2.2f, 0.24f,
                                 ARGB(255, 255, 210, 90), ARGB(255, 80, 20, 60),
                                 true);
            } else {
                int winner = g.c[0].fell ? 1 : 0;
                const char* who = winner == 0 ? "P1" : "P2";
                char buf[32];
                snprintf(buf, sizeof(buf), "%s SCORES!", who);
                drawTextCentered(buf, 0.0f, 2.2f, 0.22f,
                                 g.c[winner].colorLight, ARGB(255, 30, 12, 40),
                                 true);
            }
        } else if (g.state == GameState::MatchOver) {
            const char* who = g.matchWinner == 0 ? "P1" : "P2";
            char buf[32];
            snprintf(buf, sizeof(buf), "%s WINS THE MATCH!", who);
            drawTextCentered(buf, 0.0f, 2.2f, 0.17f, g.c[g.matchWinner].colorLight,
                             ARGB(255, 30, 12, 40), true);
        } else if (g.state == GameState::Playing && g.playT < 0.7f) {
            drawTextCentered("GO!", 0.0f, 2.0f, 0.4f, ARGB(255, 120, 255, 170),
                             ARGB(255, 20, 80, 40), true);
        }
    }

    flushRects();
}