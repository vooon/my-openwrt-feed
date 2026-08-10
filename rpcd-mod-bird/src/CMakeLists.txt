cmake_minimum_required(VERSION 3.30)
PROJECT(rpcd-mod-bird)
ADD_DEFINITIONS(-Os -Wall -Werror --std=gnu99 -g3 -Wmissing-declarations)

SET(SOURCES bird.c)

ADD_LIBRARY(rpcd-mod-bird SHARED ${SOURCES})

SET_TARGET_PROPERTIES(rpcd-mod-bird PROPERTIES OUTPUT_NAME bird PREFIX "")
INSTALL(TARGETS rpcd-mod-bird LIBRARY DESTINATION lib/rpcd)