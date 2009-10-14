# -*- mode: sh -*-

VERS := $(shell head -1 debian/changelog  | sed -e 's:^.*(::' -e 's:).*::')
NAME ?= alarmd
ROOT ?= /tmp/test-$(NAME)

PREFIX       ?= /usr
BINDIR       ?= $(PREFIX)/bin
SBINDIR      ?= $(PREFIX)/sbin
DLLDIR       ?= $(PREFIX)/lib
LIBDIR       ?= $(PREFIX)/lib
INCDIR       ?= $(PREFIX)/include/$(NAME)

DOCDIR       ?= $(PREFIX)/share/doc/$(NAME)
MANDIR       ?= $(PREFIX)/share/man

CACHEDIR     ?= /var/cache/alarmd
DEVDOCDIR    ?= $(PREFIX)/share/doc/libalarm-doc
PKGCFGDIR    ?= $(PREFIX)/lib/pkgconfig

UPSTART_EVENT_DIR    ?= /etc/event.d
XSESSION_DEFAULT_DIR ?= /etc/X11/Xsession.d
XSESSION_ACTDEAD_DIR ?= /etc/X11/Xsession.actdead

BACKUP_DIR   ?= /etc/osso-backup

CUD_DIR      ?= /etc/osso-cud-scripts
RFS_DIR      ?= /etc/osso-rfs-scripts

DBUS_DIR     ?= /etc/dbus-1/system.d

# This is set also in Doxyfile ...
DOXYWORK     ?= doxygen_output

# Note: if so-version is changed, you need also to edit
# - debian/control: fix libalarmN package names
# - debian/rules:   fix libalarmN package names and install dirs
SO ?= .so.2

TEMPLATE_COPY = sed\
 -e 's:@NAME@:${NAME}:g'\
 -e 's:@VERS@:${VERS}:g'\
 -e 's:@ROOT@:${ROOT}:g'\
 -e 's:@PREFIX@:${PREFIX}:g'\
 -e 's:@BINDIR@:${BINDIR}:g'\
 -e 's:@LIBDIR@:${LIBDIR}:g'\
 -e 's:@DLLDIR@:${DLLDIR}:g'\
 -e 's:@INCDIR@:${INCDIR}:g'\
 -e 's:@DOCDIR@:${DOCDIR}:g'\
 -e 's:@MANDIR@:${MANDIR}:g'\
 -e 's:@SBINDIR@:${SBINDIR}:g'\
 -e 's:@CACHEDIR@:${CACHEDIR}:g'\
 -e 's:@DEVDOCDIR@:${DEVDOCDIR}:g'\
 -e 's:@PKGCFGDIR@:${PKGCFGDIR}:g'\
 -e 's:@BACKUP_DIR@:${BACKUP_DIR}:g'\
 < $< > $@

# ----------------------------------------------------------------------------
# PKG CONFIG does not separate CPPFLAGS from CFLAGS -> we need them properly
#            separated so that various optional preprosessing stuff works
# ----------------------------------------------------------------------------

PKG_NAMES := \
 glib-2.0 \
 dbus-glib-1 \
 dbus-1 \
 conic \
 osso-systemui-dbus \
 mce \
 dsme_dbus_if \
 statusbar-alarm

# allow maintenance targets to be "build" outside scratchbox
# or build environment without pkg-config warnings about
# missing packages...
maintenance  = clean distclean normalize P undoc dead_code lgpl
intersection = $(strip $(foreach w,$1, $(filter $w,$2)))
ifneq ($(call intersection,$(maintenance),$(MAKECMDGOALS)),)
PKG_CONFIG   ?= true
endif

PKG_CONFIG   ?= pkg-config
PKG_CFLAGS   := $(shell $(PKG_CONFIG) --cflags $(PKG_NAMES))
PKG_LDLIBS   := $(shell $(PKG_CONFIG) --libs   $(PKG_NAMES))
PKG_CPPFLAGS := $(filter -D%,$(PKG_CFLAGS)) $(filter -I%,$(PKG_CFLAGS))
PKG_CFLAGS   := $(filter-out -I%, $(filter-out -D%, $(PKG_CFLAGS)))

# ----------------------------------------------------------------------------
# Global Flags
# ----------------------------------------------------------------------------

CPPFLAGS += -DENABLE_LOGGING=3
CPPFLAGS += -DVERS='"${VERS}"'
CPPFLAGS += -D_GNU_SOURCE
CPPFLAGS += -DALARMD_MANGLE_MEMBERS

CFLAGS   += -Wall
CFLAGS   += -Wmissing-prototypes
CFLAGS   += -std=c99
CFLAGS   += -Os
CFLAGS   += -g
CFLAGS   += -Werror

LDFLAGS  += -g

LDLIBS   += -Wl,--as-needed

CPPFLAGS += $(PKG_CPPFLAGS)
CFLAGS   += $(PKG_CFLAGS)
LDLIBS   += $(PKG_LDLIBS)

## QUARANTINE CPPFLAGS += -DDEAD_CODE
## QUARANTINE CFLAGS   += -Wno-unused-function

USE_LIBTIME ?= y#

ifeq ($(wildcard /usr/include/clockd/libtime.h),)
CPPFLAGS += -DHAVE_LIBTIME=0
CPPFLAGS += -DUSE_LIBTIME=0
else
CPPFLAGS += -DHAVE_LIBTIME=1
ifeq ($(USE_LIBTIME),y)
CPPFLAGS += -DUSE_LIBTIME=1
LDLIBS   += -ltime
endif
endif

# ----------------------------------------------------------------------------
# Top Level Targets
# ----------------------------------------------------------------------------

TARGETS += libalarm.a
TARGETS += libalarm$(SO)
TARGETS += alarmd
TARGETS += alarmclient
TARGETS += alarmtool
TARGETS += alarmd.wrapper

FLOW_GRAPHS = $(foreach e,.png .pdf .eps,\
		  $(addsuffix $e,$(addprefix $1,.fun .mod .api .top)))

EXTRA += $(call FLOW_GRAPHS, alarmclient)
EXTRA += $(call FLOW_GRAPHS, alarmd)

.PHONY: build clean distclean mostlyclean install debclean

build:: $(TARGETS)

extra:: $(EXTRA)

all:: build extra

clean:: mostlyclean
	$(RM) $(TARGETS) $(EXTRA)

distclean:: clean

mostlyclean::
	$(RM) *~ *.o src/*.o

install:: $(addprefix install-,alarmd alarmclient libalarm libalarm-dev libalarm-doc)

debclean:: distclean
	fakeroot ./debian/rules clean

# ----------------------------------------------------------------------------
# Dependency Scanning
# ----------------------------------------------------------------------------

.PHONY: depend

depend:: autogenerated_headers
	gcc -MM $(CPPFLAGS) src/*.c | ./build_tools/depend_filter.py -dsrc > .depend

ifneq ($(MAKECMDGOALS),depend)
include .depend
endif

# ----------------------------------------------------------------------------
# Autogenerated Files
# ----------------------------------------------------------------------------

autogenerated_headers:: src/clockd_dbus.inc
autogenerated_headers:: src/alarmd_config.h

src/clockd_dbus.inc : /usr/include/clockd/libtime.h
	grep > $@ 'define.*CLOCK' $<

src/alarmd_config.h         : src/alarmd_config.h.tpl Makefile
	$(TEMPLATE_COPY)

pkg-config-scripts/alarm.pc : pkg-config-scripts/alarm.pc.tpl Makefile
	$(TEMPLATE_COPY)

osso-backup/alarmd.conf     : osso-backup/alarmd.conf.tpl Makefile
	$(TEMPLATE_COPY)

osso-cud-scripts/alarmd.sh  : osso-cud-scripts/alarmd.sh.tpl Makefile
	$(TEMPLATE_COPY)

osso-rfs-scripts/alarmd.sh  : osso-rfs-scripts/alarmd.sh.tpl Makefile
	$(TEMPLATE_COPY)

distclean::
	$(RM) osso-cud-scripts/alarmd.sh
	$(RM) osso-rfs-scripts/alarmd.sh
	$(RM) src/alarmd_config.h
	$(RM) src/clockd_dbus.inc
	$(RM) osso-backup/alarmd.conf
	$(RM) pkg-config-scripts/alarm.pc

# ----------------------------------------------------------------------------
# Implicit build rules
# ----------------------------------------------------------------------------

%.1.gz  : %.1     ; gzip $< -9 -c > $@
%.8.gz  : %.8     ; gzip $< -9 -c > $@

%.dot   : %.dot.manual   ; cp $< $@
%.cflow : %.cflow.manual ; cp $< $@

%       : src/%.o ; $(CC) -o $@ $^ $(LDFLAGS) $(LDLIBS)

%$(SO): LDFLAGS += -shared -Wl,-soname,$@

%$(SO):
	$(CC) -o $@  $^ $(LDFLAGS) $(LDLIBS)

%.a:
	$(AR) ru $@ $^

%.pic.o : CFLAGS += -fPIC
%.pic.o : CFLAGS += -fvisibility=hidden
%.pic.o : %.c
	@echo "Compile: dynamic: $<"
	@$(CC) -o $@ -c $< $(CPPFLAGS) $(CFLAGS)

%.o     : %.c
	@echo "Compile: static: $<"
	@$(CC) -o $@ -c $< $(CPPFLAGS) $(CFLAGS)

%.dead.o     : %.c
	@echo "Compile: static: $<"
	@$(CC) -o $@ -c $< -DDEAD_CODE $(CPPFLAGS) $(CFLAGS)

# ----------------------------------------------------------------------------
# Implicit install rules
# ----------------------------------------------------------------------------

install-%-man1:
	$(if $<, install -m755 -d $(ROOT)$(MANDIR)/man1)
	$(if $<, install -m644 $^ $(ROOT)$(MANDIR)/man1)
install-%-man8:
	$(if $<, install -m755 -d $(ROOT)$(MANDIR)/man8)
	$(if $<, install -m644 $^ $(ROOT)$(MANDIR)/man8)

install-%-bin:
	$(if $<, install -m755 -d $(ROOT)$(BINDIR))
	$(if $<, install -m755 $^ $(ROOT)$(BINDIR))

install-%-sbin:
	$(if $<, install -m755 -d $(ROOT)$(SBINDIR))
	$(if $<, install -m755 $^ $(ROOT)$(SBINDIR))

install-%-lib:
	$(if $<, install -m755 -d $(ROOT)$(LIBDIR))
	$(if $<, install -m755 $^ $(ROOT)$(LIBDIR))

install-%-dll:
	$(if $<, install -m755 -d $(ROOT)$(DLLDIR))
	$(if $<, install -m755 $^ $(ROOT)$(DLLDIR))

install-%-inc:
	$(if $<, install -m755 -d $(ROOT)$(INCDIR))
	$(if $<, install -m755 $^ $(ROOT)$(INCDIR))

install-%-event:
	$(if $<, install -m755 -d $(ROOT)$(UPSTART_EVENT_DIR))
	$(if $<, install -m644 $^ $(ROOT)$(UPSTART_EVENT_DIR))

install-%-xsession-default:
	$(if $<, install -m755 -d $(ROOT)$(XSESSION_DEFAULT_DIR))
	$(if $<, install -m755 $^ $(ROOT)$(XSESSION_DEFAULT_DIR))

install-%-xsession-actdead:
	$(if $<, install -m755 -d $(ROOT)$(XSESSION_ACTDEAD_DIR))
	$(if $<, install -m755 $^ $(ROOT)$(XSESSION_ACTDEAD_DIR))

install-%-backup-config:
	$(if $<, install -m755 -d $(ROOT)$(BACKUP_DIR)/applications)
	$(if $<, install -m644 $^ $(ROOT)$(BACKUP_DIR)/applications)

install-%-backup-restore:
	$(if $<, install -m755 -d $(ROOT)$(BACKUP_DIR)/restore.d/always)
	$(if $<, install -m755 $^ $(ROOT)$(BACKUP_DIR)/restore.d/always)

install-%-cud-scripts:
	$(if $<, install -m755 -d $(ROOT)$(CUD_DIR))
	$(if $<, install -m755 $^ $(ROOT)$(CUD_DIR))

install-%-rfs-scripts:
	$(if $<, install -m755 -d $(ROOT)$(RFS_DIR))
	$(if $<, install -m755 $^ $(ROOT)$(RFS_DIR))

install-%-dbus-system:
	$(if $<, install -m755 -d $(ROOT)$(DBUS_DIR))
	$(if $<, install -m644 $^ $(ROOT)$(DBUS_DIR))

# ----------------------------------------------------------------------------
# Doxygen output
# ----------------------------------------------------------------------------

.PHONY: dox
dox:	; doxygen 1>doxygen.log
#dox:	; doxygen 2>&1 1>doxygen.log | ./build_tools/doxygen_filter.py

clean::
	$(RM) doxygen.log
distclean::
	$(RM) -r $(DOXYWORK)

# ----------------------------------------------------------------------------
# Miscellaneous Documentation & Images
# ----------------------------------------------------------------------------

FLOWFLAGS += -Xlogging
FLOWFLAGS += -Xxutil
## QUARANTINE FLOWFLAGS += -Xcodec
## QUARANTINE FLOWFLAGS += -Xdbusif
## QUARANTINE FLOWFLAGS += -Xinifile
## QUARANTINE FLOWFLAGS += -Xevent
## QUARANTINE FLOWFLAGS += -Xaction
## QUARANTINE FLOWFLAGS += -Xstrbuf
## QUARANTINE FLOWFLAGS += -Xunique
## QUARANTINE FLOWFLAGS += -Xsighnd

## QUARANTINE FLOWFLAGS += -Mdbusif=libalarm
FLOWFLAGS += -Mclient=libalarm
## QUARANTINE FLOWFLAGS += -Mevent=libalarm
## QUARANTINE FLOWFLAGS += -Maction=libalarm

CFLOW := cflow -v --omit-arguments
#CFLOW += -is
#CFLOW += -sDBusMessage:type

%.eps     : %.ps    ; ps2epsi $< $@
%.ps      : %.dot   ; dot -Tps  $< -o $@
%.pdf     : %.dot   ; dot -Tpdf $< -o $@
%.png     : %.dot   ; dot -Tpng $< -o $@
%.mod.dot : %.cflow ; ./build_tools/cflow_filter.py -c1 $(FLOWFLAGS) <$< >$@
%.fun.dot : %.cflow ; ./build_tools/cflow_filter.py -c0 $(FLOWFLAGS) <$< >$@
%.api.dot : %.cflow ; ./build_tools/cflow_filter.py -i1 $(FLOWFLAGS) <$< >$@
%.top.dot : %.cflow ; ./build_tools/cflow_filter.py -t1 $(FLOWFLAGS) <$< >$@
%.cflow   :         ; $(CFLOW) -o $@ $^

clean::
	$(RM) *.cflow
	$(RM) *.mod.dot *.fun.dot *.api.dot
	$(RM) *.mod.pdf *.fun.pdf *.api.pdf
	$(RM) *.mod.png *.fun.png *.api.png
	$(RM) man/*.1.gz man/*.8.gz

# ----------------------------------------------------------------------------
# libalarm
# ----------------------------------------------------------------------------

# we use dbus_message_iter_get_array_len() because
# as far as I can see we have to -> suppress warnings
dbusif.o dbusif.pic.o : CFLAGS += -Wno-deprecated-declarations

libalarm_src =\
	src/client.c\
	src/event.c\
	src/dbusif.c\
	src/strbuf.c\
	src/action.c\
	src/codec.c\
	src/logging.c\
	src/recurrence.c\
	src/serialize.c\
	src/ticker.c\
	src/attr.c

libalarm_obj = $(libalarm_src:.c=.o)

libalarm.a : $(libalarm_obj)
	ar ru $@ $^

libalarm$(SO) : $(libalarm_obj:.o=.pic.o)
	$(CC) -o $@ -shared  $^ $(LDFLAGS) $(LDLIBS)

# ----------------------------------------------------------------------------
# alarmd
# ----------------------------------------------------------------------------

alarmd_src =\
	src/alarmd.c\
	src/mainloop.c\
	src/sighnd.c\
	src/queue.c\
	src/server.c\
	src/inifile.c\
	src/symtab.c\
	src/unique.c\
	src/escape.c\
	src/hwrtc.c\
	src/xutil.c\
	src/ipc_statusbar.c\
	src/ipc_dsme.c\
	src/ipc_systemui.c\
	src/ipc_icd.c\
	src/ipc_exec.c

#	src/exithack.c\

alarmd_obj = $(alarmd_src:.c=.o)

alarmd : LDLIBS += -lrt -ldl

alarmd : $(alarmd_obj) libalarm.a

alarmd.cflow : $(alarmd_src) $(libalarm_src) #*.h

## QUARANTINE FLOWFLAGS_ALARMD += -Xcodec,symtab,unique,inifile,xutil
FLOWFLAGS_ALARMD += -xserver_make_reply
FLOWFLAGS_ALARMD += -xserver_parse_args
alarmd.mod.dot alarmd.fun.dot : FLOWFLAGS += $(FLOWFLAGS_ALARMD)

# ----------------------------------------------------------------------------
# alarmd.wrapper
# ----------------------------------------------------------------------------

alarmd.wrapper : src/alarmd.wrapper.sh
	$(TEMPLATE_COPY)
	chmod a+rx $@

# ----------------------------------------------------------------------------
# alarmclient
# ----------------------------------------------------------------------------

alarmclient_src = \
	src/alarmclient.c\
	src/xutil.c
alarmclient_obj = $(alarmclient_src:.c=.o) src/ipc_dsme.dead.o

alarmclient : LDLIBS += -lrt
alarmclient : $(alarmclient_obj) libalarm.a
#alarmclient : $(alarmclient_obj) libalarm$(SO)

## QUARANTINE alarmclient.o : CFLAGS += -Wno-unused-function
## QUARANTINE alarmclient.o : CFLAGS += -Wno-error

alarmclient.cflow : $(alarmclient_src) $(libalarm_src)

# ----------------------------------------------------------------------------
# alarmtool
# ----------------------------------------------------------------------------

alarmtool_src = \
	src/alarmtool.c
alarmtool_obj = $(alarmtool_src:.c=.o)

alarmtool : LDLIBS += -lrt
#alarmtool : $(alarmtool_obj) libalarm.a
alarmtool : $(alarmtool_obj) libalarm$(SO)

#alarmtool.o : CFLAGS += -Wno-unused-function

alarmtool.cflow : $(alarmtool_src) $(libalarm_src)

# ----------------------------------------------------------------------------
# alarmd.deb
# ----------------------------------------------------------------------------

install-alarmd-man8:\
  man/alarmd.8.gz

install-alarmd-sbin:\
  alarmd.wrapper\
  alarmd

install-alarmd-event:

install-alarmd-xsession-default:\
  xsession/50alarmd\
  xsession/03alarmd

install-alarmd-xsession-actdead:\
  xsession/03alarmd

## QUARANTINE install-alarmd-xsession-default:\
## QUARANTINE   xsession/03alarmd-act-dead\
## QUARANTINE   xsession/31alarmd-user

install-alarmd-xsession:\
  install-alarmd-xsession-default\
  install-alarmd-xsession-actdead

install-alarmd-dbus-system:\
  dbus-config/system.d/alarmd.conf

install-alarmd-backup-config:\
  osso-backup/alarmd.conf

install-alarmd-backup-restore:\
  osso-backup/alarmd_restart.sh

install-alarmd-backup: $(addprefix install-alarmd-backup-, config restore)

install-alarmd-cud-scripts: osso-cud-scripts/alarmd.sh
install-alarmd-rfs-scripts: osso-rfs-scripts/alarmd.sh

install-alarmd-appkiller:\
  install-alarmd-cud-scripts\
  install-alarmd-rfs-scripts

install-alarmd:: $(addprefix install-alarmd-,\
  sbin event xsession appkiller backup man8 dbus-system)
	mkdir -p $(ROOT)/$(CACHEDIR)

# ----------------------------------------------------------------------------
# alarmclient.deb
# ----------------------------------------------------------------------------

install-alarmclient-bin: alarmclient
install-alarmclient-man1:\
  man/alarmclient.1.gz

install-alarmclient:: $(addprefix install-alarmclient-, bin man1)

# ----------------------------------------------------------------------------
# libalarm.deb
# ----------------------------------------------------------------------------

install-libalarm-dll: libalarm$(SO)

install-libalarm:: $(addprefix install-libalarm-, dll)

# ----------------------------------------------------------------------------
# libalarm-dev.deb
# ----------------------------------------------------------------------------

install-libalarm-dev-inc: \
	src/libalarm.h \
	src/libalarm-async.h \
	src/alarm_dbus.h

install-libalarm-dev-lib: libalarm.a

install-libalarm-dev-pkg-config: pkg-config-scripts/alarm.pc
	install -m755 -d $(ROOT)$(PKGCFGDIR)
	install -m644 $^ $(ROOT)$(PKGCFGDIR)/

install-libalarm-dev:: $(addprefix install-libalarm-dev-, lib inc pkg-config)
	ln -sf libalarm$(SO) $(ROOT)$(LIBDIR)/libalarm.so

# ----------------------------------------------------------------------------
# libalarm-doc.deb
# ----------------------------------------------------------------------------

install-libalarm-doc-html: dox
	install -m755 -d $(ROOT)$(DEVDOCDIR)/html
	install -m644 $(DOXYWORK)/html/* $(ROOT)$(DEVDOCDIR)/html/

install-libalarm-doc-man: dox
	install -m755 -d $(ROOT)$(MANDIR)/man3
	install -m644 $(DOXYWORK)/man/man3/* $(ROOT)$(MANDIR)/man3/

install-libalarm-doc:: $(addprefix install-libalarm-doc-, html man)

# ----------------------------------------------------------------------------
# Prototype Scanning
# ----------------------------------------------------------------------------

.PHONY: P Q

%.proto : %.q  ; cproto -E0 $< | prettyproto.py > $@ $*.c
%.q     : %.c  ; $(CC) $(CPPFLAGS) -E $< > $@

Q: $(patsubst %.c,%.q,$(wildcard *.c))
P: $(patsubst %.c,%.proto,$(wildcard *.c))

clean::
	$(RM) *.proto *.q

# ----------------------------------------------------------------------------
# CTAG scanning
# ----------------------------------------------------------------------------

.PHONY: tags

tags:
	ctags */*.[ch] *.inc

distclean::
	$(RM) tags

# ----------------------------------------------------------------------------
# Check that headers are includable on their own
# ----------------------------------------------------------------------------

hdrchk:
	./build_tools/check_header_files.py $(CPPFLAGS) -- src/*.h

# ----------------------------------------------------------------------------
# Autogenerated debian files
# ----------------------------------------------------------------------------

DEBIAN_FILES = debian/alarmd.init debian/alarmd.postinst

debian-files:: $(DEBIAN_FILES)

clean::
	$(RM) $(DEBIAN_FILES)

debian/alarmd.init : alarmd.init
	$(TEMPLATE_COPY)

debian/alarmd.postinst : alarmd.postinst
	$(TEMPLATE_COPY)

event.d/alarmd : alarmd.event.tpl
	mkdir -p event.d
	$(TEMPLATE_COPY)

# ----------------------------------------------------------------------------
# Debug apps
# ----------------------------------------------------------------------------

.PHONY: fakes
fakes:
	make -C testing

distclean::
	make -C testing distclean

clean::
	make -C testing clean

skeleton.cflow : skeleton/skeleton.c
	$(CFLOW) -o $@.tmp $^
	sed -e 's:skeleton_::g' < $@.tmp >$@

# ----------------------------------------------------------------------------
# Dead code detection
# ----------------------------------------------------------------------------

.PHONY: dead_code

dead_code:: dead_code.txt
	tac $<

dead_code.txt : dead_code.xref
	./build_tools/dead_code.py < $< > $@

dead_code.xref :  $(wildcard src/*.c src/*.h)
	cflow -x $^ > $@ --preprocess=./build_tools/dead_cpp.py

distclean::
	$(RM) dead_code.txt dead_code.xref

# ----------------------------------------------------------------------------
# Libalarm dynamic dependencies
# ----------------------------------------------------------------------------

libalarm.dot : $(libalarm_obj)
	./build_tools/resolve_syms.py $^ > $@

alarmd.dot : $(alarmd_obj) $(libalarm_obj)
	./build_tools/resolve_syms.py $^ > $@

distclean::
	$(RM) libalarm.dot alarmd.dot
	$(RM) libalarm.png alarmd.png

# ----------------------------------------------------------------------------
# Check files that are missing the LGPL template
# ----------------------------------------------------------------------------

.PHONY: lgpl

lgpl:
	./build_tools/find_non_lgpl_files.py

# ----------------------------------------------------------------------------
# Whitespace normalization
# ----------------------------------------------------------------------------

.PHONY: normalize

normalize_files += xsession/03alarmd
normalize_files += xsession/03alarmd-act-dead
normalize_files += xsession/31alarmd-user
normalize_files += osso-backup/alarmd.conf.tpl
normalize_files += osso-backup/alarmd_restart.sh
normalize_files += pkg-config-scripts/alarm.pc.tpl
normalize_files += osso-rfs-scripts/alarmd.sh.tpl
normalize_files += osso-cud-scripts/alarmd.sh.tpl

normalize:
	crlf -a */*.[ch] */*.py
	crlf -a src/*.tpl src/*.inc
	crlf -M Makefile testing/Makefile debian/rules
	crlf -t -e -k debian/changelog debian/control debian/copyright
	crlf -a $(normalize_files)
	crlf -a alarmd.init

# ----------------------------------------------------------------------------
# Generate manpages
# ----------------------------------------------------------------------------

.PHONY: generate_manfiles
generate_manfiles: alarmd alarmclient
	sp_gen_manfile -Dsource=alarmd -Dsection=1 -c ./alarmclient > man/alarmclient.1
	sp_gen_manfile -Dsource=alarmd -Dsection=8 -c ./alarmd > man/alarmd.8

#eof
