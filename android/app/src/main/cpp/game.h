#pragma once

#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <vector>

struct Vec2 {
    float x = 0.0f, y = 0.0f;

    Vec2() = default;
    Vec2(float a, float b) : x(a), y(b) {}

    Vec2 operator+(const Vec2& o) const { return {x + o.x, y + o.y}; }
    Vec2 operator-(const Vec2& o) const { return {x - o.x, y - o.y}; }
    Vec2 operator*(float s) const { return {x * s, y * s}; }
    Vec2 operator/(float s) const { return {x / s, y / s}; }
    Vec2& operator+=(const Vec2& o) {
        x += o.x;
        y += o.y;
        return *this;
    }
    Vec2& operator-=(const Vec2& o) {
        x -= o.x;
        y -= o.y;
        return *this;
    }
    Vec2& operator*=(float s) {
        x *= s;
        y *= s;
        return *this;
    }
    float dot(const Vec2& o) const { return x * o.x + y * o.y; }
    float len2() const { return x * x + y * y; }
    float len() const { return std::sqrt(len2()); }
    Vec2 perp() const { return {-y, x}; }
    Vec2 normalized() const {
        float l = len();
        if (l < 1e-6f) return {1.0f, 0.0f};
        return {x / l, y / l};
    }
    static Vec2 clampMag(const Vec2& v, float m) {
        float l2 = v.len2();
        if (l2 > m * m) {
            float l = std::sqrt(l2);
            return v * (m / l);
        }
        return v;
    }
};

enum class GameState { Menu, Countdown, Playing, RoundOver, MatchOver };

struct InputState {
    Vec2 joy{0.0f, 0.0f};
    bool punch = false;
    bool kick = false;
    bool jump = false;
};

struct Particle {
    Vec2 pos;
    Vec2 vel;
    float life = 0.0f;
    float maxLife = 1.0f;
    float r = 0.05f;
    uint32_t color = 0xFFFFFFFFu;
};

// Part indices for a character's jelly body
enum Part {
    PART_HEAD = 0,
    PART_TORSO,
    PART_HAND_L,
    PART_HAND_R,
    PART_FOOT_L,
    PART_FOOT_R,
    PART_COUNT
};

struct Character {
    Vec2 p[PART_COUNT];   // current positions (verlet)
    Vec2 p0[PART_COUNT];  // previous positions (verlet)
    int face = 1;
    bool grounded = false;
    float punchT = 0.0f;   // active punch timer
    float kickT = 0.0f;    // active kick timer
    float pullT = 0.0f;    // limb recoil timer
    int punchSide = 0;     // 0 = left hand, 1 = right hand
    Vec2 punchDir{1.0f, 0.0f};
    bool hitDone = false;
    float aiTimer = 0.0f;
    bool fell = false;
    uint32_t color = 0xFF4CA6FFu;
    uint32_t colorDark = 0xFF205C9Eu;
    uint32_t colorLight = 0xFFADDFFFu;

    void reset(float x, uint32_t main, uint32_t dark, uint32_t light);
    Vec2 velOf(int i) const { return p[i] - p0[i]; }
};

class Game {
public:
    Game();

    void resetRound(bool resetScores);
    void step(float dt);
    void setInput(int player, const InputState& in);
    void tapMenu(const Vec2& world);

    // state exposed for the renderer / bridge
    GameState state = GameState::Menu;
    int mode = 0;  // 0 = 1P vs bot, 1 = 2P local
    float countdownT = 0.0f;
    float stateT = 0.0f;
    float playT = 0.0f;
    float time = 0.0f;
    float shake = 0.0f;
    int score[2] = {0, 0};
    int roundWins = 3;
    int matchWinner = -1;
    Character c[2];
    std::vector<Particle> particles;
    InputState input[2];
    Vec2 joyAnchor[2]{{0.0f, 0.0f}, {0.0f, 0.0f}};
    bool joyActive[2] = {false, false};
    float aspect = 1.6f;

    static constexpr float WORLD_HALF = 7.0f;
    static constexpr float GAP = 1.05f;
    static constexpr float FLOOR_Y = 0.0f;
    static constexpr float WALL_H = 6.0f;
    static constexpr float PIT_KILL = -2.4f;

private:
    void stepPhysics(float dt);
    void stepAI(float dt);
    void constrainChar(Character& ch, float dt);
    void collideWorld(Character& ch);
    void tryPunch(Character& ch, int self);
    void tryKick(Character& ch, int self);
    void spawnSparks(const Vec2& pos, const Character& a, const Character& b, int n);
    void spawnFallBurst(const Vec2& pos, const Character& ch);
    void solveRopeConstraint(Vec2& a, Vec2& b, float rest, float stiff);
};
