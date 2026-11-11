cmake_minimum_required(VERSION 3.21)
project(sonde VERSION 0.2.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

include(GNUInstallDirs)

set(SONDE_QML_INSTALL_DIR "${CMAKE_INSTALL_DATADIR}/sonde/qml")

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

# QML 优先从源码目录加载（开发期改完即生效）；安装后用 share/sonde/qml。
# 运行时还可用环境变量 SONDE_QML_DIR 覆盖。
target_compile_definitions(sonde PRIVATE
    SONDE_QML_DIR="${CMAKE_SOURCE_DIR}/ui/qml"
    SONDE_INSTALL_QML_DIR="${CMAKE_INSTALL_FULL_DATADIR}/sonde/qml")

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

install(TARGETS sonde RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
install(DIRECTORY "${CMAKE_SOURCE_DIR}/ui/qml/"
        DESTINATION "${SONDE_QML_INSTALL_DIR}")
install(FILES "${CMAKE_SOURCE_DIR}/data/sonde.desktop"
        DESTINATION "${CMAKE_INSTALL_DATADIR}/applications")
install(FILES "${CMAKE_SOURCE_DIR}/data/sonde.svg"
        DESTINATION "${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps")
