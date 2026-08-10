cmake_minimum_required(VERSION 3.30)
PROJECT(rpcd-mod-bmx7)
ADD_DEFINITIONS(-Os -Wall -Werror --std=gnu99 -g3 -Wmissing-declarations)

SET(SOURCES bmx7.c)

ADD_LIBRARY(rpcd-mod-bmx7 SHARED ${SOURCES})

SET_TARGET_PROPERTIES(rpcd-mod-bmx7 PROPERTIES OUTPUT_NAME bmx7 PREFIX "")
INSTALL(TARGETS rpcd-mod-bmx7 LIBRARY DESTINATION lib/rpcd)