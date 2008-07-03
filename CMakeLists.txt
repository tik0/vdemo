cmake_minimum_required(VERSION 2.4)
if(COMMAND cmake_policy)
  cmake_policy(SET CMP0003 NEW)
endif(COMMAND cmake_policy)

MARK_AS_ADVANCED(CMAKE_BACKWARDS_COMPATIBILITY)
MARK_AS_ADVANCED(EXECUTABLE_OUTPUT_PATH)
MARK_AS_ADVANCED(LIBRARY_OUTPUT_PATH)
MARK_AS_ADVANCED(CMAKE_BUILD_TYPE)

#INCLUDE(UsePkgConfig)

###
### Project name, features, and destination
###

PROJECT(vdemo)
SET(PROGNAME vdemo)
SET(PROGVERSION 0.2)
SET(LIBNAME rdsdata)
SET(PACKET airobots)
SET(PREFIX ${CMAKE_INSTALL_PREFIX})

SET(BINDIR "${PREFIX}/bin")
SET(INCLUDEDIR "${PREFIX}/include")
SET(MANDIR "${PREFIX}/man")
SET(LIBDIR "${PREFIX}/lib")
SET(VDEMO_root "${PREFIX}/lib/vdemo")
SET(DATADIR "${PREFIX}/share/${PACKET}")


CONFIGURE_FILE(vdemo.pc.in vdemo.pc)
CONFIGURE_FILE(vdemo.in vdemo)
CONFIGURE_FILE(vdemo2.in vdemo2)
CONFIGURE_FILE(vdemo_component.in vdemo_component)
INSTALL(FILES vdemo.pc DESTINATION ${LIBDIR}/pkgconfig)
INSTALL(PROGRAMS vdemo vdemo2 vdemo_component DESTINATION ${BINDIR})
INSTALL(PROGRAMS vdemo_base.sh vdemo_controller.tcl vdemo2_controller.tcl vdemo_standard_component_suffix.sh DESTINATION ${VDEMO_root})


