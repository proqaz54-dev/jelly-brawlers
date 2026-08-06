cmake_minimum_required(VERSION 3.22.1)
project(jelly_brawlers LANGUAGES CXX)

add_library(jelly SHARED
        game.cpp
        renderer.cpp
        native_bridge.cpp
)

target_compile_features(jelly PRIVATE cxx_std_17)
target_compile_options(jelly PRIVATE -Wall -Wextra -O2 -ffunction-sections -fdata-sections)
target_link_options(jelly PRIVATE -Wl,--gc-sections)

find_library(log_lib log)
target_link_libraries(jelly android log EGL GLESv2 ${log_lib})