cmake_minimum_required(VERSION 3.21)
project(sonde VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Qml QuickControls2 Gui)
find_package(Threads REQUIRED)

set(SONDE_RUST_LIB "${CMAKE_SOURCE_DIR}/rustcore/target/release/libsondecore.a")

# 系统里没有打包 Corrosion，所以直接用自定义 target 调 cargo。
# 这是最朴素的做法，没有任何额外依赖。
add_custom_target(sonde_rust ALL
    COMMAND cargo build --release
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/rustcore"
    BYPRODUCTS "${SONDE_RUST_LIB}"
    COMMENT "cargo build --release (sondecore)"
    VERBATIM)

add_executable(sonde
    ui/main.cpp
    ui/bridge.cpp
    ui/bridge.h
    ui/messagemodel.cpp
    ui/messagemodel.h)

target_include_directories(sonde PRIVATE "${CMAKE_SOURCE_DIR}/ui")

# QML 从源码目录加载，开发期改完即生效，无需重新编译。
target_compile_definitions(sonde PRIVATE
    SONDE_QML_DIR="${CMAKE_SOURCE_DIR}/ui/qml")

add_dependencies(sonde sonde_rust)

target_link_libraries(sonde PRIVATE
    Qt6::Quick
    Qt6::Qml
    Qt6::QuickControls2
    "${SONDE_RUST_LIB}"
    Threads::Threads
    ${CMAKE_DL_LIBS}
    m)
