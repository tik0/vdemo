CMAKE_MINIMUM_REQUIRED(VERSION 2.4)

PROJECT(vdemo)
SET(PROGNAME vdemo)
SET(PROGVERSION 0.5)
SET(LIBNAME rdsdata)
SET(PACKET airobots)

SET(PREFIX ${CMAKE_INSTALL_PREFIX})
SET(BINDIR "${PREFIX}/bin")
SET(INCLUDEDIR "${PREFIX}/include")
SET(LIBDIR "${PREFIX}/lib")
SET(VDEMO_root "${PREFIX}/lib/vdemo")

ADD_CUSTOM_COMMAND(OUTPUT vdemo_cert.pem
                  COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/generate_certificate.sh vdemo_cert.pem)
ADD_CUSTOM_TARGET(vdemo_cert ALL DEPENDS vdemo_cert.pem)

CONFIGURE_FILE(vdemo.pc.in vdemo.pc @ONLY)
CONFIGURE_FILE(vdemo2.in vdemo2 @ONLY)
CONFIGURE_FILE(vdemo_component.in vdemo_component @ONLY)

INSTALL(FILES ${PROJECT_BINARY_DIR}/vdemo.pc DESTINATION ${LIBDIR}/pkgconfig)
INSTALL(FILES ${PROJECT_BINARY_DIR}/vdemo_cert.pem DESTINATION ${VDEMO_root})
INSTALL(DIRECTORY webdata DESTINATION ${VDEMO_root})
INSTALL(PROGRAMS ${PROJECT_BINARY_DIR}/vdemo2 ${PROJECT_BINARY_DIR}/vdemo_component DESTINATION ${BINDIR})
INSTALL(PROGRAMS vdemo_base.sh vdemo2_controller.tcl vdemo_standard_component_suffix.sh vdemo_remove_logfiles vdemo_controller.py DESTINATION ${VDEMO_root})
