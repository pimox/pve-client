PACKAGE=pve-client
PKGVER=0.1
PKGREL=1

DEB=${PACKAGE}_${PKGVER}-${PKGREL}_all.deb

DESTDIR=

PERL5_DIR=${DESTDIR}/usr/share/perl5
LIB_DIR=${DESTDIR}/usr/share/${PACKAGE}
DOCDIR=${DESTDIR}/usr/share/doc/${PACKAGE}
BASHCOMPLDIR=${DESTDIR}/usr/share/bash-completion/completions/

PVE_COMMON_FILES=    		\
	CLIHandler.pm		\
	JSONSchema.pm		\
	PTY.pm			\
	RESTHandler.pm		\
	SafeSyslog.pm		\
	SectionConfig.pm	\

all: ${DEB}

.PHONY: deb
deb ${DEB}:
	rm -rf build
	rsync -a debian build
	make DESTDIR=./build install
	cd build; dpkg-buildpackage -rfakeroot -b -us -uc
	lintian ${DEB}

install:  pve-api-definition.dat
	install -d -m 0755 ${PERL5_DIR}/PVE/APIClient
	# install library tools from pve-common
	for i in ${PVE_COMMON_FILES}; do install -m 0644 PVE/APIClient/$$i ${PERL5_DIR}/PVE/APIClient; done
	# install pveclient
	install -D -m 0644 PVE/APIClient/Tools.pm ${PERL5_DIR}/PVE/APIClient/Tools.pm
	install -D -m 0644 PVE/APIClient/Helpers.pm ${PERL5_DIR}/PVE/APIClient/Helpers.pm
	install -D -m 0644 PVE/APIClient/Config.pm ${PERL5_DIR}/PVE/APIClient/Config.pm
	install -D -m 0644 PVE/APIClient/Commands/remote.pm ${PERL5_DIR}/PVE/APIClient/Commands/remote.pm
	install -D -m 0644 PVE/APIClient/Commands/lxc.pm ${PERL5_DIR}/PVE/APIClient/Commands/lxc.pm
	install -D -m 0644 PVE/APIClient/Commands/config.pm ${PERL5_DIR}/PVE/APIClient/Commands/config.pm
	install -D -m 0644 PVE/APIClient/Commands/list.pm ${PERL5_DIR}/PVE/APIClient/Commands/list.pm
	install -D -m 0644 PVE/APIClient/Commands/GuestStatus.pm ${PERL5_DIR}/PVE/APIClient/Commands/GuestStatus.pm
	install -D -m 0644 pve-api-definition.dat ${LIB_DIR}/pve-api-definition.dat
	install -D -m 0755 pveclient ${DESTDIR}/usr/bin/pveclient
	install -D -m 0644 pveclient.bash-completion ${BASHCOMPLDIR}/pveclient


update-pve-common:
	for i in ${PVE_COMMON_FILES}; do cp ../pve-common/src/PVE/$$i PVE/APIClient/; done
	for i in ${PVE_COMMON_FILES}; do sed -i 's/PVE::/PVE::APIClient::/g' PVE/APIClient/$$i; done
	# Remove INotify from CLIHandler.pm
	sed -i 's/use PVE::APIClient::INotify;//' PVE/APIClient/CLIHandler.pm


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
