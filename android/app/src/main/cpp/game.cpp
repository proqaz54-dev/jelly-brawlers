#include "game.h"

#include <algorithm>

namespace {

constexpr float GRAV = 22.0f;
constexpr float MOVE_SPEED = 3.4f;
constexpr float JUMP_SPEED = 9.2f;
constexpr int CONSTRAINT_ITERS = 6;
constexpr float DAMPING = 0.985f;

struct Rope {
    int a, b;
    float rest;
};

const Rope BODY[7] = {
    {PART_HEAD, PART_TORSO, 0.55f},
    {PART_HEAD, PART_HAND_L, 0.78f},
    {PART_HEAD, PART_HAND_R, 0.78f},
    {PART_TORSO, PART_HAND_L, 0.82f},
    {PART_TORSO, PART_HAND_R, 0.82f},
    {PART_TORSO, PART_FOOT_L, 0.80f},
    {PART_TORSO, PART_FOOT_R, 0.80f},
};

struct Seg {
    Vec2 a, b;
};

const Seg SEGS[] = {
    {{-Game::WORLD_HALF, 0.0f}, {-Game::GAP, 0.0f}},
    {{Game::GAP, 0.0f}, {Game::WORLD_HALF, 0.0f}},
    {{-Game::GAP, 0.0f}, {-Game::GAP, -1.5f}},
    {{Game::GAP, 0.0f}, {Game::GAP, -1.5f}},
    {{-Game::WORLD_HALF, 0.0f}, {-Game::WORLD_HALF, Game::WALL_H}},
    {{Game::WORLD_HALF, 0.0f}, {Game::WORLD_HALF, Game::WALL_H}},
    {{-Game::WORLD_HALF, -1.5f}, {-Game::GAP, -1.5f}},
    {{Game::GAP, -1.5f}, {Game::WORLD_HALF, -1.5f}},
};

inline uint32_t rgbMix(uint32_t a, uint32_t b, float t) {
    float ca[4] = {float((a >> 24) & 0xFF), float((a >> 16) & 0xFF),
                   float((a >> 8) & 0xFF), float(a & 0xFF)};
    float cb[4] = {float((b >> 24) & 0xFF), float((b >> 16) & 0xFF),
                   float((b >> 8) & 0xFF), float(b & 0xFF)};
    uint32_t r = 0;
    for (int i = 0; i < 4; ++i)
        r |= ((uint32_t)(ca[i] + (cb[i] - ca[i]) * t) & 0xFF) << (24 - i * 8);
    return r;
}

}  // namespace

void Character::reset(float x, uint32_t main, uint32_t dark, uint32_t light) {
    color = main;
    colorDark = dark;
    colorLight = light;
    fell = false;
    face = x < 0.0f ? 1 : -1;
    punchT = kickT = pullT = 0.0f;
    hitDone = false;
    grounded = false;
    float y = 0.45f;
    Vec2 pos[PART_COUNT] = {
        {x, y + 0.62f},  // head
        {x, y},          // torso
        {x - 0.34f, y + 0.45f},
        {x + 0.34f, y + 0.45f},
        {x - 0.22f, y - 0.55f},
        {x + 0.22f, y - 0.55f},
    };
    for (int i = 0; i < PART_COUNT; ++i) {
        p[i] = pos[i];
        p0[i] = pos[i];
    }
}

Game::Game() {
    resetRound(true);
}

void Game::setInput(int player, const InputState& in) {
    if (player >= 0 && player < 2) input[player] = in;
}

void Game::resetRound(bool resetScores) {
    if (resetScores) {
        score[0] = score[1] = 0;
    }
    for (auto& p : particles) p.life = 0.0f;
    c[0].reset(-2.3f, 0xFF4CA6FFu, 0xFF205C9Eu, 0xFFADDFFFu);
    c[1].reset(2.3f, 0xFFFF6A4Du, 0xFF9E2D1Au, 0xFFFFC7ABu);
    countdownT = 1.6f;
    stateT = 0.0f;
    state = GameState::Countdown;
}

void Game::step(float dt) {
    dt = std::min(dt, 1.0f / 30.0f);
    time += dt;
    shake = std::max(0.0f, shake - dt * 1.6f);

    // Menu: no physics
    if (state == GameState::Menu) return;

    if (state == GameState::Countdown) {
        countdownT -= dt;
        stepPhysics(dt);
        if (countdownT <= 0.0f) {
            countdownT = 0.0f;
            playT = 0.0f;
            state = GameState::Playing;
        }
        return;
    }

    if (state == GameState::RoundOver) {
        stateT -= dt;
        stepPhysics(dt);
        if (stateT <= 0.0f) {
            if (score[0] >= roundWins || score[1] >= roundWins) {
                matchWinner = score[0] > score[1] ? 0 : 1;
                score[0] = score[1] = 0;
                state = GameState::MatchOver;
                stateT = 2.5f;
            } else {
                resetRound(false);
            }
        }
        return;
    }

    if (state == GameState::MatchOver) {
        stateT -= dt;
        if (stateT <= 0.0f) {
            stateT = 0.0f;
            resetRound(true);
        }
        return;
    }

    // Playing
    stepAI(dt);
    stepPhysics(dt);
    playT += dt;

    for (int i = 0; i < 2; ++i) {
        if (c[i].fell) continue;
        bool out = false;
        for (int k = 0; k < PART_COUNT; ++k) {
            if (c[i].p[k].y < PIT_KILL) { out = true; break; }
        }
        if (!out) continue;
        c[i].fell = true;
        spawnFallBurst({c[i].p[PART_TORSO].x, PIT_KILL - 0.5f}, c[i]);
        int other = 1 - i;
        bool bothFell = c[other].fell;
        if (bothFell) {
            state = GameState::RoundOver;
            stateT = 1.0f;
        } else {
            score[other]++;
            state = GameState::RoundOver;
            stateT = 1.5f;
        }
    }
}

void Game::stepAI(float dt) {
    if (mode != 0) return;  // 2P local, no AI
    Character& bot = c[1];
    Character& foe = c[0];
    InputState& in = input[1];
    in.joy = {0.0f, 0.0f};
    in.punch = in.kick = in.jump = false;

    if (bot.fell) {
        in.joy = {0.0f, 0.0f};
        return;
    }

    Vec2 d = foe.p[PART_TORSO] - bot.p[PART_TORSO];
    float dx = d.x;
    float dist = d.len();
    bot.aiTimer -= dt;

    // Try to stay on the platform, avoid edges
    float edgeDist = Game::WORLD_HALF - 0.7f;
    if (bot.p[PART_TORSO].x > edgeDist) {
        in.joy = {-1.0f, 0.0f};
        if (bot.aiTimer <= 0.0f) {
            bot.aiTimer = 0.6f + std::rand() % 100 * 0.01f;
            in.kick = true;
        }
        return;
    }
    if (bot.p[PART_TORSO].x < -edgeDist) {
        in.joy = {1.0f, 0.0f};
        return;
    }

    in.joy = {dx < 0.0f ? -1.0f : 1.0f, 0.0f};
    if (std::fabs(dx) < 1.3f) {
        if (bot.aiTimer <= 0.0f) {
            bot.aiTimer = 0.28f + (std::rand() % 100) * 0.003f;
            int r = std::rand() % 100;
            if (r < 55)
                in.punch = true;
            else if (r < 75)
                in.kick = true;
            else
                in.jump = true;
        }
    }
    (void)dist;
}

void Game::stepPhysics(float dt) {
    const float dt2 = dt * dt;
    for (int i = 0; i < 2; ++i) {
        Character& ch = c[i];

        // Verlet integrate
        for (int k = 0; k < PART_COUNT; ++k) {
            Vec2 vel = (ch.p[k] - ch.p0[k]) * DAMPING;
            ch.p0[k] = ch.p[k];
            ch.p[k] += vel + Vec2(0.0f, -GRAV) * dt2;
        }

        // grounded detection
        ch.grounded = false;
        for (int k = 0; k < 2; ++k) {
            int fi = k == 0 ? PART_FOOT_L : PART_FOOT_R;
            if (ch.p[fi].y <= FLOOR_Y + 0.12f && std::fabs(ch.p[fi].x) > GAP)
                ch.grounded = true;
        }

        bool active = (state == GameState::Playing) && !ch.fell;

        if (active) {
            InputState& in = input[i];
            // movement
            Vec2 mv = Vec2::clampMag(in.joy, 1.0f);
            ch.p[PART_TORSO] += mv * (MOVE_SPEED * dt * (ch.grounded ? 1.0f : 0.45f));
            ch.p[PART_HEAD] += mv * (MOVE_SPEED * dt * 0.35f);

            // jump
            if (in.jump && ch.grounded) {
                ch.p[PART_FOOT_L] += Vec2(0.0f, JUMP_SPEED) * dt;
                ch.p[PART_FOOT_R] += Vec2(0.0f, JUMP_SPEED) * dt;
                ch.p[PART_TORSO] += Vec2(0.0f, JUMP_SPEED * 0.7f) * dt;
                in.jump = false;
            }

            if (in.punch) { tryPunch(ch, i); in.punch = false; }
            if (in.kick) { tryKick(ch, i); in.kick = false; }
        }

        constrainChar(ch, dt);
        collideWorld(ch);
    }

    // hits between bodies
    for (int i = 0; i < 2; ++i) {
        Character& ch = c[i];
        if (ch.fell || ch.hitDone) continue;
        if (ch.punchT <= 0.0f && ch.kickT <= 0.0f) continue;
        int foe = 1 - i;
        int limb = ch.kickT > 0.0f
                       ? (ch.punchDir.x > 0.05f ? PART_FOOT_R : PART_FOOT_L)
                       : (ch.punchSide == 0 ? PART_HAND_L : PART_HAND_R);
        Vec2 limbPos = ch.p[limb];
        float hr = ch.kickT > 0.0f ? 0.52f : 0.46f;
        float power = ch.kickT > 0.0f ? 10.0f : 8.0f;
        const float weight[PART_COUNT] = {0.75f, 1.0f, 0.5f, 0.5f, 0.6f, 0.6f};
        Vec2 dir = ch.punchDir;
        for (int k = 0; k < PART_COUNT; ++k) {
            Vec2 d = c[foe].p[k] - limbPos;
            if (d.len2() > hr * hr) continue;
            for (int m = 0; m < PART_COUNT; ++m) {
                Vec2 jitter((std::rand() % 200 - 100) * 0.004f,
                            (std::rand() % 200 - 100) * 0.004f);
                c[foe].p[m] += (dir * (power * weight[m]) + jitter) * dt;
            }
            ch.hitDone = true;
            shake = std::max(shake, 0.35f);
            spawnSparks(limbPos, ch, c[foe], 14);
            break;
        }
    }

    // particles
    for (auto& p : particles) {
        p.vel.y -= GRAV * dt;
        p.pos += p.vel * dt;
        p.life -= dt;
    }
    particles.erase(std::remove_if(particles.begin(), particles.end(),
                                   [](const Particle& p) { return p.life <= 0.0f; }),
                    particles.end());
}

void Game::tryPunch(Character& ch, int self) {
    if (ch.punchT > 0.0f || ch.kickT > 0.0f || ch.pullT > 0.0f) return;
    int foe = 1 - self;
    Vec2 target = c[foe].p[PART_TORSO] - ch.p[PART_TORSO];
    Vec2 dir = target.len2() > 1e-4f ? target.normalized() : Vec2(ch.face, 0.0f);
    ch.punchDir = dir;
    ch.punchSide = ch.punchSide == 0 ? 1 : 0;  // alternate hands
    ch.punchT = 0.16f;
    ch.hitDone = false;
}

void Game::tryKick(Character& ch, int self) {
    if (ch.punchT > 0.0f || ch.kickT > 0.0f || ch.pullT > 0.0f) return;
    int foe = 1 - self;
    Vec2 target = c[foe].p[PART_TORSO] - ch.p[PART_TORSO];
    Vec2 dir = target.len2() > 1e-4f ? target.normalized() : Vec2(ch.face, 0.0f);
    ch.punchDir = dir;
    ch.kickT = 0.15f;
    ch.hitDone = false;
}

void Game::constrainChar(Character& ch, float dt) {
    // limb extension during punch / kick, plus recoil
    int handIdx = ch.punchSide == 0 ? PART_HAND_L : PART_HAND_R;
    const float armMul =
        ch.punchT > 0.0f ? 1.55f : (ch.pullT > 0.0f ? 0.55f : 1.0f);

    if (ch.punchT > 0.0f) {
        ch.p[handIdx] += ch.punchDir * 26.0f * dt;
        ch.punchT -= dt;
        if (ch.punchT <= 0.0f) ch.pullT = 0.15f;
    } else if (ch.pullT > 0.0f) {
        ch.p[handIdx] -= ch.punchDir * 18.0f * dt;
        ch.pullT -= dt;
    }

    int footIdx = PART_FOOT_L;
    Vec2 kickDir = ch.punchDir;
    if (ch.kickT > 0.0f) {
        int side = (kickDir.x > 0.05f) ? PART_FOOT_R : PART_FOOT_L;
        footIdx = side;
        ch.p[side] += kickDir * 24.0f * dt;
        ch.kickT -= dt;
        if (ch.kickT <= 0.0f) ch.pullT = 0.16f;
    }

    // rope constraints
    for (int it = 0; it < CONSTRAINT_ITERS; ++it) {
        for (const Rope& rope : BODY) {
            float rest = rope.rest;
            bool isArm = (rope.a == PART_HEAD || rope.a == PART_TORSO) &&
                         (rope.b == PART_HAND_L || rope.b == PART_HAND_R);
            if (isArm && ch.punchT > 0.0f) {
                int side = rope.b == PART_HAND_L ? PART_HAND_L : PART_HAND_R;
                if (side == handIdx) rest *= armMul;
            }
            if (!isArm && rope.b == footIdx && ch.kickT > 0.0f) rest *= 1.5f;

            solveRopeConstraint(ch.p[rope.a], ch.p[rope.b], rest, 0.62f);
        }
    }
}

void Game::collideWorld(Character& ch) {
    for (int k = 0; k < PART_COUNT; ++k) {
        Vec2& p = ch.p[k];
        float r = (k == PART_HEAD) ? 0.36f : (k == PART_TORSO ? 0.34f : 0.20f);
        for (int it = 0; it < 2; ++it) {
            for (const Seg& s : SEGS) {
                Vec2 ab = s.b - s.a;
                float t = ((p - s.a).dot(ab)) / ab.dot(ab);
                t = std::clamp(t, 0.0f, 1.0f);
                Vec2 cp = s.a + ab * t;
                Vec2 d = p - cp;
                float d2 = d.len2();
                if (d2 >= r * r || d2 < 1e-9f) continue;
                float dist = std::sqrt(d2);
                Vec2 n = d / dist;
                p += n * (r - dist);
                // friction on horizontal ground
                if (n.y > 0.7f) {
                    ch.p0[k].x = p.x - (p.x - ch.p0[k].x) * 0.45f;
                }
            }
        }
    }
}

void Game::solveRopeConstraint(Vec2& a, Vec2& b, float rest, float stiff) {
    Vec2 d = b - a;
    float dist = d.len();
    if (dist < 1e-6f) return;
    Vec2 n = d / dist;
    float diff = (dist - rest) * stiff;
    Vec2 dx = n * (diff * 0.5f);
    a += dx;
    b -= dx;
}

void Game::tapMenu(const Vec2& world) {
    if (state != GameState::Menu) return;
    Vec2 b0(-2.4f, -1.4f);
    Vec2 b1(2.4f, -1.4f);
    if ((world - b0).len() < 0.95f) {
        mode = 0;
        resetRound(true);
    } else if ((world - b1).len() < 0.95f) {
        mode = 1;
        resetRound(true);
    }
}

void Game::spawnSparks(const Vec2& pos, const Character& a, const Character& b, int n) {
    for (int i = 0; i < n; ++i) {
        Particle pt;
        pt.pos = pos;
        float ang = (std::rand() % 628) / 100.0f;
        float sp = 3.0f + (std::rand() % 100) * 0.05f;
        pt.vel = {std::cos(ang) * sp, std::sin(ang) * sp + 2.0f};
        pt.life = pt.maxLife = 0.3f + (std::rand() % 100) * 0.004f;
        pt.r = 0.06f + (std::rand() % 50) * 0.002f;
        pt.color = rgbMix(a.color, b.color, 0.5f);
        particles.push_back(pt);
    }
}

void Game::spawnFallBurst(const Vec2& pos, const Character& ch) {
    for (int i = 0; i < 26; ++i) {
        Particle pt;
        pt.pos = pos;
        float ang = (std::rand() % 628) / 100.0f;
        float sp = 2.0f + (std::rand() % 120) * 0.05f;
        pt.vel = {std::cos(ang) * sp, std::sin(ang) * sp};
        pt.life = pt.maxLife = 0.5f + (std::rand() % 100) * 0.005f;
        pt.r = 0.08f + (std::rand() % 60) * 0.002f;
        pt.color = ch.colorLight;
        particles.push_back(pt);
    }
}