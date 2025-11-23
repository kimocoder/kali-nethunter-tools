# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2021 Iñigo Martinez <inigomartinez@gmail.com>

libname = 'qrtr-glib'

libqrtr_glib_inc = include_directories('.')

headers = files(
  'libqrtr-glib.h',
  'qrtr-bus.h',
  'qrtr-client.h',
  'qrtr-node.h',
  'qrtr-types.h',
  'qrtr-utils.h',
)

install_headers(
  headers,
  install_dir: qrtr_glib_pkgincludedir,
)

version_header = configure_file(
  input: 'qrtr-version.h.in',
  output: '@BASENAME@',
  configuration: version_conf,
  install_dir: qrtr_glib_pkgincludedir,
)

sources = files(
  'qrtr-bus.c',
  'qrtr-client.c',
  'qrtr-node.c',
  'qrtr-utils.c',
)

c_flags = [
  '-DLIBQRTR_GLIB_COMPILATION',
  '-DG_LOG_DOMAIN="Qrtr"',
  '-DLIBEXEC_PATH="@0@"'.format(qrtr_prefix / qrtr_libexecdir),
]

libqrtr_glib = library(
  libname,
  version: qrtr_glib_version,
  sources: sources + [version_header],
  include_directories: top_inc,
  dependencies: glib_deps,
  c_args: c_flags,
  install: true,
)

libqrtr_glib_dep = declare_dependency(
  sources: version_header,
  include_directories: libqrtr_glib_inc,
  dependencies: glib_deps,
  link_with: libqrtr_glib,
)

pkg.generate(
  libraries: libqrtr_glib,
  version: qrtr_version,
  name: libname,
  description: 'Library to use and monitor the QRTR bus',
  subdirs: qrtr_glib_include_subdir,
  # FIXME: produced by the inhability of meson to use internal dependencies
  requires: ['glib-2.0', 'gobject-2.0', 'gio-2.0'],
  variables: 'exec_prefix=${prefix}',
)

if enable_gir
  incs = [
    'Gio-2.0',
    'GLib-2.0',
    'GObject-2.0',
  ]

  ns = 'Qrtr'

  libqrtr_glib_gir = gnome.generate_gir(
    libqrtr_glib,
    sources: sources + headers,
    includes: incs,
    namespace: ns,
    nsversion: qrtr_gir_version,
    identifier_prefix: ns,
    symbol_prefix: ns.to_lower() + '_',
    extra_args: c_flags + ['--identifier-prefix=' + ns.to_upper()],
    header: 'libqrtr-glib.h',
    export_packages: libname,
    install: true,
  )
endif
