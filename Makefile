VDEMO_root?=/vol/vampire/demos/vdemo_base

SCRIPTS=        \
		vdemo \
		vdemo.config \
                vdemo_base.sh \
                vdemo_component \
                vdemo_controller.tcl \
                vdemo_standard_component_suffix.sh \
		vdemo2 \
                vdemo2_controller.tcl

INSTALL_SCRIPTS=$(SCRIPTS:%=./.install/%)


.PHONY: all install

all:	$(INSTALL_SCRIPTS)

$(INSTALL_SCRIPTS): ./.install

./.install:
	mkdir -p ./.install

./.install/%:	%
	cat $< | sed "s#@INSTALLPATH@#$(VDEMO_root)#g" > $@



install:	$(INSTALL_SCRIPTS)
	-install -m 2775 -d $(VDEMO_root)
	install -m 755 $^ $(VDEMO_root)

clean:
	rm -rf ./.install