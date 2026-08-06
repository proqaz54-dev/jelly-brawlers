#pragma once

#include "game.h"

class Renderer {
public:
    bool init();
    void render(const Game& g, int viewW, int viewH);

private:
    void drawBackground(const Game& g, float halfW, float halfH);
    void drawArena(const Game& g, float time);
    void drawCharacter(const Game& g, const Character& ch, float time);
    void drawParticles(const Game& g);
    void drawHud(const Game& g, float halfW, float halfH);
    void drawTouchUi(const Game& g, float halfW, float halfH);
    void drawMenu(const Game& g, float halfW, float halfH);

    void drawCircle(float x, float y, float r, uint32_t color, float sx = 1.0f,
                    float sy = 1.0f, float rot = 0.0f);
    void drawRect(float x0, float y0, float x1, float y1, uint32_t color);
    void flushRects();
    void drawText(const char* s, float x, float y, float scale,
                  uint32_t color);
    void drawTextOutlined(const char* s, float x, float y, float scale,
                          uint32_t color, uint32_t outline);
    void drawTextCentered(const char* s, float cx, float y, float scale,
                          uint32_t color, uint32_t outline, bool outlined);

    unsigned int progCircle_ = 0;
    unsigned int progRect_ = 0;
    unsigned int vboCircle_ = 0;
    unsigned int vboRect_ = 0;
    int uMvpCircle_ = -1;
    int uColorCircle_ = -1;
    int uMvpRect_ = -1;
};
