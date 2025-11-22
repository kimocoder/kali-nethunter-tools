#
# Makefile for libcap
#
topdir=$(shell pwd)
include Make.Rules

#
# flags
#

all test sudotest install clean: %: %-here
	$(MAKE) -C libcap $@
ifneq ($(PAM_CAP),no)
	$(MAKE) -C pam_cap $@
endif
ifeq ($(GOLANG),yes)
	$(MAKE) -C go $@
	rm -f cap/go.sum
endif
	$(MAKE) -C tests $@
	$(MAKE) -C progs $@
	$(MAKE) -C doc $@

all-here:

test-here:

sudotest-here:

install-here:

clean-here:
	$(LOCALCLEAN)

gomods-update:
	./gomods.sh v$(GOMAJOR).$(VERSION).$(MINOR)

distclean: clean
	$(DISTCLEAN)
	@echo "CONFIRM Go package cap has right version dependency on cap/psx:"
	for x in $$(find . -name go.mod); do $(BUILD_FGREP) -v "module" $$x | $(BUILD_FGREP) "kernel.org/pub/linux/libs/security/libcap" > /dev/null || continue ; $(BUILD_FGREP) "v$(GOMAJOR).$(VERSION).$(MINOR)" $$x  > /dev/null && continue ; echo "$$x is not updated. Try running: make gomods-update" ; exit 1 ; done
	@echo "ALL go.mod files updated"
	@echo "Confirm headers export current version"
	$(BUILD_FGREP) "#define LIBCAP_MAJOR $(VERSION)" libcap/include/sys/capability.h
	$(BUILD_FGREP) "#define LIBCAP_MINOR $(MINOR)" libcap/include/sys/capability.h
	$(BUILD_FGREP) "#define LIBPSX_MAJOR $(VERSION)" psx/psx_syscall.h
	$(BUILD_FGREP) "#define LIBPSX_MINOR $(MINOR)" psx/psx_syscall.h
	@echo "Now validate that everything is checked in to a clean tree.."
	test -z "$$(git status --ignored -s)"
	@echo "All good!"

release: distclean
	cd .. && ln -s libcap libcap-$(VERSION).$(MINOR) && tar cvf libcap-$(VERSION).$(MINOR).tar --exclude patches libcap-$(VERSION).$(MINOR)/* && rm libcap-$(VERSION).$(MINOR)

ktest: all
	$(MAKE) -C kdebug test

distcheck: distclean
	./distcheck.sh
	$(MAKE) DYNAMIC=no COPTS="-D_FORTIFY_SOURCE=2 -O1 -g" clean test
	$(MAKE) DYNAMIC=yes clean all test sudotest
	$(MAKE) DYNAMIC=no COPTS="-O2 -std=c89" clean all test sudotest
	$(MAKE) PAM_CAP=no CC=musl-gcc clean all test sudotest
	$(MAKE) CC=clang clean all test sudotest
	$(MAKE) clean all test sudotest
	$(MAKE) distclean

morgangodoc:
	@echo "Now the release is made, you may want to hurry go.dev up by"
	@echo "pressing the request button on this page:"
	@echo
	@echo "  https://pkg.go.dev/kernel.org/pub/linux/libs/security/libcap/cap@v$(GOMAJOR).$(VERSION).$(MINOR)"
	@echo
	@echo "This will cause a go.dev documentation update more quickly."

morganrelease: distcheck
	@echo "sign the main library tag three times: legacy DSA key; newer RSA (kernel.org automation) key; official ed25519 key"
	git tag -u 0D23D34C577B08C4082CFD76430C5CFF993116B1 -s sig-libcap-$(VERSION).$(MINOR) -m "official tag for libcap-$(VERSION).$(MINOR)"
	git tag -u AF7402BC38CC10E6885C1FCA421784ABD41A6DF2 -s libcap-$(VERSION).$(MINOR) -m "legacy tag for libcap-$(VERSION).$(MINOR)"
	git tag -u 38A644698C69787344E954CE29EE848AE2CCF3F4 -s libcap-korg-$(VERSION).$(MINOR) -m "kernel.org automation tag for libcap-$(VERSION).$(MINOR)"
	@echo "The following are for the Go module tracking (the stylized tag names have semantic meaning)."
	git tag -u 0D23D34C577B08C4082CFD76430C5CFF993116B1 -s v$(GOMAJOR).$(VERSION).$(MINOR) -m "version tag for the 'libcap' Go base directory associated with libcap-$(VERSION).$(MINOR)"
	git tag -u 0D23D34C577B08C4082CFD76430C5CFF993116B1 -s psx/v$(GOMAJOR).$(VERSION).$(MINOR) -m "stable version tag for the 'psx' Go package associated with libcap-$(VERSION).$(MINOR)"
	git tag -u 0D23D34C577B08C4082CFD76430C5CFF993116B1 -s cap/v$(GOMAJOR).$(VERSION).$(MINOR) -m "stable version tag for the 'cap' Go package associated with libcap-$(VERSION).$(MINOR)"
	$(MAKE) release
	@echo "sign the tar file using korg key - so it can be uploaded to kernel.org"
	cd .. && gpg -sba -u 38A644698C69787344E954CE29EE848AE2CCF3F4 libcap-$(VERSION).$(MINOR).tar
	$(MAKE) morgangodoc
