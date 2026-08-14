cmake_minimum_required(VERSION 3.13)

PROJECT(inotify C)
ADD_DEFINITIONS(-Os -Wall -Wextra --std=gnu99 -ffunction-sections -D_GNU_SOURCE -Wno-unused-parameter -Wno-unused-function)

IF(APPLE)
  SET(UCODE_MODULE_LINK_OPTIONS "LINKER:-undefined,dynamic_lookup")
ELSE()
  SET(CMAKE_SHARED_LIBRARY_LINK_C_FLAGS "-Wl,--gc-sections")
ENDIF()

FIND_PATH(ucode_include_dir NAMES ucode/module.h)
INCLUDE_DIRECTORIES(${ucode_include_dir})

ADD_LIBRARY(inotify MODULE inotify.c)
SET_TARGET_PROPERTIES(inotify PROPERTIES OUTPUT_NAME inotify PREFIX "")
TARGET_LINK_OPTIONS(inotify PRIVATE ${UCODE_MODULE_LINK_OPTIONS})

INSTALL(TARGETS inotify LIBRARY DESTINATION lib/ucode)