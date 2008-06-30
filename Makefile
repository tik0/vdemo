#VDEMO_root?=/vol/vampire/demos/vdemo_base
#bindir?=/tmp/VDEMO-FAKE-INSTALL

VDEMO_root=$(bindir)

SCRIPTS=        \
		vdemo \
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
	@(if [ -z "$(bindir)" ]; then \
		echo 'set $$(bindir) in order to install' >&2 ;\
		exit 1;\
	fi)	
	cat $< | sed "s#@bindir@#$(bindir)#g"  | \
		sed "s#@datadir@#$(datadir)#g"  | \
		sed "s#@libdir@#$(libdir)#g"  | \
		sed "s#@sharedstatedir@#$(sharedstatedir)#g" > $@ || rm -f "$@"





install:	$(INSTALL_SCRIPTS) 
	-install -m 2775 -d $(VDEMO_root)
	install -m 755 $^ $(VDEMO_root)
	rm -rf ./.install

clean:
	rm -rf ./.install