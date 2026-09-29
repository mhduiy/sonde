cmake_minimum_required(VERSION 3.21)
project(sonde VERSION 0.2.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Qml QuickControls2 Gui)
find_package(Threads REQUIRED)

set(SONDE_RUST_LIB "${CMAKE_SOURCE_DIR}/rustcore/target/release/libsondecore.a")

# 系统里没有打包 Corrosion，所以直接用自定义 target 调 cargo。
add_custom_target(sonde_rust ALL
    COMMAND cargo build --release
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/rustcore"
    BYPRODUCTS "${SONDE_RUST_LIB}"
    COMMENT "cargo build --release (sondecore)"
    VERBATIM)

set(SONDE_UI_SOURCES
    ui/main.cpp
    ui/bridge.cpp
    ui/bridge.h
    ui/objecttree.cpp
    ui/objecttree.h
    ui/theme.cpp
    ui/theme.h
    ui/messagemodel.cpp
    ui/messagemodel.h)

add_executable(sonde ${SONDE_UI_SOURCES})

target_include_directories(sonde PRIVATE "${CMAKE_SOURCE_DIR}/ui")

# QML 从源码目录加载，开发期改完即生效，无需重新编译。
target_compile_definitions(sonde PRIVATE
    SONDE_QML_DIR="${CMAKE_SOURCE_DIR}/ui/qml")

add_dependencies(sonde sonde_rust)

# DTK6（Deepin Tool Kit）：让 QML 控件用系统原生样式，并接管深浅色
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(DTK6GUI QUIET dtk6gui)
endif()
if(DTK6GUI_FOUND)
    target_include_directories(sonde PRIVATE ${DTK6GUI_INCLUDE_DIRS})
    target_link_libraries(sonde PRIVATE ${DTK6GUI_LINK_LIBRARIES})
    target_compile_definitions(sonde PRIVATE SONDE_WITH_DTK=1)
    message(STATUS "找到 DTK6 Gui：控件使用 DTK 原生样式")
else()
    message(STATUS "未找到 DTK6 Gui：控件回退到 Qt 默认样式")
endif()

target_link_libraries(sonde PRIVATE
    Qt6::Quick
    Qt6::Qml
    Qt6::QuickControls2
    "${SONDE_RUST_LIB}"
    Threads::Threads
    ${CMAKE_DL_LIBS}
    m)
