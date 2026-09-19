cmake_minimum_required(VERSION 3.13)

PROJECT(sqlite C)
ADD_DEFINITIONS(-Os -Wall -Wextra --std=gnu99 -ffunction-sections -D_GNU_SOURCE -Wno-unused-parameter -Wno-unused-function)

IF(APPLE)
  SET(UCODE_MODULE_LINK_OPTIONS "LINKER:-undefined,dynamic_lookup")
ELSE()
  SET(CMAKE_SHARED_LIBRARY_LINK_C_FLAGS "-Wl,--gc-sections")
ENDIF()

FIND_PATH(ucode_include_dir NAMES ucode/module.h)
INCLUDE_DIRECTORIES(${ucode_include_dir})

FIND_PACKAGE(PkgConfig REQUIRED)
PKG_CHECK_MODULES(SQLITE3 REQUIRED IMPORTED_TARGET sqlite3)

ADD_LIBRARY(sqlite MODULE sqlite.c)
SET_TARGET_PROPERTIES(sqlite PROPERTIES OUTPUT_NAME sqlite PREFIX "")
TARGET_LINK_LIBRARIES(sqlite PRIVATE PkgConfig::SQLITE3)
TARGET_LINK_OPTIONS(sqlite PRIVATE ${UCODE_MODULE_LINK_OPTIONS})

INSTALL(TARGETS sqlite LIBRARY DESTINATION lib/ucode)
