PACKAGE=pve-client
PKGVER=0.1
PKGREL=1

DEB=${PACKAGE}_${PKGVER}-${PKGREL}_all.deb

DESTDIR=

LIB_DIR=${DESTDIR}/usr/share/${PACKAGE}
DOCDIR=${DESTDIR}/usr/share/doc/${PACKAGE}
BASHCOMPLDIR=${DESTDIR}/usr/share/bash-completion/completions/

all: ${DEB}

.PHONY: deb
deb ${DEB}:
	rm -rf build
	rsync -a debian build
	make DESTDIR=./build install
	cd build; dpkg-buildpackage -rfakeroot -b -us -uc
	lintian ${DEB}

install:  pve-api-definition.dat
	install -d -m 0755 ${LIB_DIR}/PVE
	# install library tools from pve-common
	install -m 0644 PVE/Tools.pm ${LIB_DIR}/PVE
	install -m 0644 PVE/SafeSyslog.pm ${LIB_DIR}/PVE
	install -m 0644 PVE/Exception.pm ${LIB_DIR}/PVE
	install -m 0644 PVE/JSONSchema.pm ${LIB_DIR}/PVE
	install -m 0644 PVE/RESTHandler.pm  ${LIB_DIR}/PVE
	install -m 0644 PVE/CLIHandler.pm ${LIB_DIR}/PVE
	install -m 0644 PVE/PTY.pm ${LIB_DIR}/PVE
	install -m 0644 PVE/SectionConfig.pm ${LIB_DIR}/PVE
	# install pveclient
	install -D -m 0644 PVE/APIClient/Helpers.pm ${LIB_DIR}/PVE/APIClient/Helpers.pm
	install -D -m 0644 PVE/APIClient/Config.pm ${LIB_DIR}/PVE/APIClient/Config.pm
	install -D -m 0644 PVE/APIClient/Commands/remote.pm ${LIB_DIR}/PVE/APIClient/Commands/remote.pm
	install -D -m 0644 PVE/APIClient/Commands/lxc.pm ${LIB_DIR}/PVE/APIClient/Commands/lxc.pm
	install -D -m 0644 pve-api-definition.dat ${LIB_DIR}/pve-api-definition.dat
	install -D -m 0755 pveclient ${DESTDIR}/usr/bin/pveclient
	install -D -m 0644 pveclient.bash-completion ${BASHCOMPLDIR}/pveclient


pve-api-definition.dat:
	./extractapi.pl > pve-api-definition.dat.tmp
	mv pve-api-definition.dat.tmp pve-api-definition.dat

#.PHONY: upload
#upload: ${DEB}
#	tar cf - ${DEB} | ssh -X repoman@repo.proxmox.com upload --product pmg,pve --dist stretch

distclean: clean

clean:
	rm -rf ./build *.deb *.changes *.buildinfo
	find . -name '*~' -exec rm {} ';'

.PHONY: dinstall
dinstall: ${DEB}
	dpkg -i ${DEB}
