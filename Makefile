PACKAGE=pve-client
PKGVER=0.1
PKGREL=1

DEB=${PACKAGE}_${PKGVER}-${PKGREL}_all.deb

DESTDIR=

PERL5DIR=${DESTDIR}/usr/share/perl5
DOCDIR=${DESTDIR}/usr/share/doc/${PACKAGE}

all: ${DEB}

.PHONY: deb
deb ${DEB}:
	rm -rf build
	rsync -a debian build
	make DESTDIR=./build install
	cd build; dpkg-buildpackage -rfakeroot -b -us -uc
	lintian ${DEB}

install:  pve-api-definition.js
	install -D -m 0644 PVE/APIClient/Helpers.pm ${PERL5DIR}/PVE/APIClient/Helpers.pm
	install -D -m 0644 pve-api-definition.js ${DESTDIR}/usr/share/${PACKAGE}/pve-api-definition.js
	install -D -m 0755 pveclient ${DESTDIR}/usr/bin/pveclient

pve-api-definition.js:
	./extractapi.pl > pve-api-definition.js.tmp
	mv pve-api-definition.js.tmp pve-api-definition.js

.PHONY: upload
upload: ${DEB}
	tar cf - ${DEB} | ssh -X repoman@repo.proxmox.com upload --product pmg,pve --dist stretch

distclean: clean

clean:
	rm -rf ./build *.deb *.changes *.buildinfo
	find . -name '*~' -exec rm {} ';'

.PHONY: dinstall
dinstall: ${DEB}
	dpkg -i ${DEB}
