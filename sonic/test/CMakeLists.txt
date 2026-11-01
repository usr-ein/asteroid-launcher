# Sonic Screwdriver: the harness that runs the launcher's QML off the watch,
# for sonic/test/test.sh. It compiles in the launcher's own QML resources and
# C++ types, and links the watch's liblipstick for the real LauncherModel.
# seed-calendar fills mkcal with the Today scene's invented events.
cmake_minimum_required(VERSION 3.6.0)
project(launcher-test LANGUAGES CXX)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_CXX_STANDARD 17)
set(launcher ${CMAKE_CURRENT_SOURCE_DIR}/../../src)
list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../../cmake)

find_package(Qt5 COMPONENTS Quick DBus REQUIRED)
find_package(Mlite5 REQUIRED)

add_executable(launcher-test
	harness.cpp
	${launcher}/applauncher.cpp
	${launcher}/applistmodel.cpp
	${launcher}/buttondoubleclick.cpp
	${launcher}/applauncherbackground.cpp
	${launcher}/resources-qml.qrc)
target_include_directories(launcher-test PRIVATE ${launcher} ${Lipstick_INCLUDE_DIRS})
target_link_libraries(launcher-test PRIVATE Qt5::Quick Qt5::DBus Mlite5::Mlite5 ${Lipstick_LIBRARIES})

find_package(PkgConfig REQUIRED)
pkg_check_modules(Calendar REQUIRED IMPORTED_TARGET libmkcal-qt5 KF5CalendarCore)
add_executable(seed-calendar seed-calendar.cpp)
target_link_libraries(seed-calendar PRIVATE Qt5::Core PkgConfig::Calendar)
