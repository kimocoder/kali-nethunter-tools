# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2021 Iñigo Martinez <inigomartinez@gmail.com>
# Copyright (C) 2021 Aleksander Morgado <aleksander@aleksander.es>

project(
  'libqrtr-glib', 'c',
  version: '1.3.0',
  license: 'LGPL-2.1-or-later',
  default_options: [
    'buildtype=debugoptimized',
    'c_std=gnu89',
    'warning_level=2',
  ],
  meson_version: '>= 0.53.0',
)

qrtr_version = meson.project_version()
version_array = qrtr_version.split('.')
qrtr_major_version = version_array[0].to_int()
qrtr_minor_version = version_array[1].to_int()
qrtr_micro_version = version_array[2].to_int()

qrtr_prefix = get_option('prefix')
qrtr_includedir = get_option('includedir')
qrtr_libexecdir = get_option('libexecdir')

qrtr_glib_include_subdir = meson.project_name()
qrtr_glib_pkgincludedir = qrtr_includedir / qrtr_glib_include_subdir

# libtool versioning for libqrtr-glib (-version-info c:r:a)
# - If the interface is unchanged, but the implementation has changed or been fixed, then increment r
# - Otherwise, increment c and zero r.
#   - If the interface has grown (that is, the new library is compatible with old code), increment a.
#   - If the interface has changed in an incompatible way (that is, functions have changed or been removed), then zero a.
current = 0
revision = 0
age = 0
qrtr_glib_version = '@0@.@1@.@2@'.format(current - age, age, revision)

qrtr_gir_version = '1.0'

gnome = import('gnome')
pkg = import('pkgconfig')

source_root = meson.current_source_dir()

top_inc = include_directories('.')

cc = meson.get_compiler('c')

# compiler flags that are always enabled, even in release builds
cc_flags = cc.get_supported_arguments([
  # warning on unused parameters is overkill, never do that
  '-Wno-unused-parameter',
  # function type cast disabled: used throughout the code especially to
  # cast GAsyncReadyCallbacks with the real object type instead of GObject
  '-Wno-cast-function-type',
  # all message protocol structs are packed, never complain about it
  '-Wno-packed',
])

# strict flags to use in debug builds
if get_option('buildtype').contains('debug')
  cc_flags += cc.get_supported_arguments([
    '-fno-strict-aliasing',
    '-Waggregate-return',
    '-Wcast-align',
    '-Wdeclaration-after-statement',
    '-Wdouble-promotion',
    '-Wduplicated-branches',
    '-Wduplicated-cond',
    '-Wfloat-equal',
    '-Wformat=2',
    '-Wformat-nonliteral',
    '-Wformat-security',
    '-Winit-self',
    '-Winline',
    '-Wjump-misses-init',
    '-Wlogical-op',
    '-Wnested-externs',
    '-Wmissing-declarations',
    '-Wmissing-format-attribute',
    '-Wmissing-include-dirs',
    '-Wmissing-noreturn',
    '-Wmissing-prototypes',
    '-Wnull-dereference',
    '-Wpointer-arith',
    '-Wredundant-decls',
    '-Wrestrict',
    '-Wreturn-type',
    '-Wshadow',
    '-Wstrict-prototypes',
    '-Wsuggest-attribute=format',
    '-Wswitch-default',
    '-Wswitch-enum',
    '-Wundef',
    '-Wunused-but-set-variable',
    '-Wwrite-strings',
  ])
endif

add_project_arguments(cc_flags, language: 'c')

glib_version = '2.56'

glib_dep = dependency('glib-2.0', version: '>= ' + glib_version)
gio_unix_dep = dependency('gio-unix-2.0')

deps = [
  glib_dep,
  dependency('gio-2.0'),
  dependency('gobject-2.0'),
]

c_flags = [
  '-DGLIB_VERSION_MIN_REQUIRED=GLIB_VERSION_' + glib_version.underscorify(),
  '-DGLIB_VERSION_MAX_ALLOWED=GLIB_VERSION_' + glib_version.underscorify(),
  '-DGLIB_DISABLE_DEPRECATION_WARNINGS',
]

glib_deps = declare_dependency(
  dependencies: deps,
  compile_args: c_flags,
)

assert(cc.has_header('linux/qrtr.h'), 'QRTR support not available in the kernel headers')

version_conf = {
  'QRTR_MAJOR_VERSION': qrtr_major_version,
  'QRTR_MINOR_VERSION': qrtr_minor_version,
  'QRTR_MICRO_VERSION': qrtr_micro_version,
  'VERSION': qrtr_version,
}

# introspection support
enable_gir = get_option('introspection')
if enable_gir
  dependency('gobject-introspection-1.0', version: '>= 0.9.6')
endif

subdir('src/libqrtr-glib')

enable_gtk_doc = get_option('gtk_doc')
if enable_gtk_doc
  subdir('docs/reference/libqrtr-glib')
endif

summary({
  'compiler': cc.get_id(),
  'cflags': cc_flags,
  'Documentation': enable_gtk_doc,
  'gobject introspection': enable_gir,
}, section: 'Build')

summary({
  'prefix': qrtr_prefix,
}, section: 'System paths')
