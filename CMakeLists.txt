CMAKE_MINIMUM_REQUIRED(VERSION 2.4)

PROJECT(vdemo)
SET(PROGNAME vdemo)
SET(PROGVERSION 0.2)
SET(LIBNAME rdsdata)
SET(PACKET airobots)

SET(PREFIX ${CMAKE_INSTALL_PREFIX})
SET(BINDIR "${PREFIX}/bin")
SET(INCLUDEDIR "${PREFIX}/include")
SET(LIBDIR "${PREFIX}/lib")
SET(VDEMO_root "${PREFIX}/lib/vdemo")

CONFIGURE_FILE(vdemo.pc.in vdemo.pc @ONLY)
CONFIGURE_FILE(vdemo2.in vdemo2 @ONLY)
CONFIGURE_FILE(vdemo_component.in vdemo_component @ONLY)

INSTALL(FILES ${PROJECT_BINARY_DIR}/vdemo.pc DESTINATION ${LIBDIR}/pkgconfig)
INSTALL(PROGRAMS ${PROJECT_BINARY_DIR}/vdemo2 ${PROJECT_BINARY_DIR}/vdemo_component DESTINATION ${BINDIR})
INSTALL(PROGRAMS vdemo_base.sh vdemo2_controller.tcl vdemo_standard_component_suffix.sh DESTINATION ${VDEMO_root})
