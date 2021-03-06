component 'ruby-2.4.4' do |pkg, settings, platform|
  pkg.version '2.4.4'
  pkg.md5sum "d50e00ccc1c9cf450f837b92d3ed3e88"

  # rbconfig-update is used to munge rbconfigs after the fact.
  pkg.add_source("file://resources/files/ruby/rbconfig-update.rb")
  if platform.is_windows?
    pkg.add_source "file://resources/files/ruby/windows_ruby_gem_wrapper.bat"
  end

  # Most ruby configuration happens in the base ruby config:
  instance_eval File.read('configs/components/_base-ruby.rb')
  # Configuration below should only be applicable to ruby 2.4.4

  #########
  # PATCHES
  #########

  base = 'resources/patches/ruby_244'
  pkg.apply_patch "#{base}/ostruct_remove_safe_nav_operator.patch"
  # This patch creates our server/client shared Gem path, used for all gems
  # that are dependencies of the shared Ruby code.
  pkg.apply_patch "#{base}/rubygems_add_puppet_vendor_dir.patch"

  if platform.is_cross_compiled?
    pkg.apply_patch "#{base}/uri_generic_remove_safe_nav_operator.patch"
  end

  if platform.is_aix?
    # TODO: Remove this patch once PA-1607 is resolved.
    pkg.apply_patch "#{base}/aix_revert_configure_in_changes.patch"

    pkg.apply_patch "#{base}/aix_ruby_libpath_with_opt_dir.patch"
    pkg.apply_patch "#{base}/aix_use_pl_build_tools_autoconf.patch"
    pkg.apply_patch "#{base}/aix_ruby_2.1_fix_make_test_failure.patch"
    pkg.apply_patch "#{base}/Remove-O_CLOEXEC-check-for-AIX-builds.patch"
  end

  if platform.is_windows?
    pkg.apply_patch "#{base}/windows_fixup_generated_batch_files.patch"
    pkg.apply_patch "#{base}/update_rbinstall_for_windows.patch"
    pkg.apply_patch "#{base}/PA-1124_add_nano_server_com_support-8feb9779182bd4285f3881029fe850dac188c1ac.patch"
    pkg.apply_patch "#{base}/windows_socket_compat_error.patch"
  end

  ####################
  # ENVIRONMENT, FLAGS
  ####################

  if platform.is_macos?
    pkg.environment 'optflags', settings[:cflags]
  elsif platform.is_windows?
    pkg.environment 'optflags', settings[:cflags] + ' -O3'
  else
    pkg.environment 'optflags', '-O2'
  end

  special_flags = " --prefix=#{settings[:ruby_dir]} --with-opt-dir=#{settings[:prefix]} "

  if platform.is_aix?
    # This normalizes the build string to something like AIX 7.1.0.0 rather
    # than AIX 7.1.0.2 or something
    special_flags += " --build=#{settings[:platform_triple]} "
  elsif platform.is_cross_compiled_linux?
    special_flags += " --with-baseruby=#{settings[:host_ruby]} "
  elsif platform.is_solaris? && platform.architecture == "sparc"
    special_flags += " --with-baseruby=#{settings[:host_ruby]} --enable-close-fds-by-recvmsg-with-peek "
  elsif platform.is_windows?
    special_flags = " CPPFLAGS='-DFD_SETSIZE=2048' debugflags=-g --prefix=#{settings[:ruby_dir]} --with-opt-dir=#{settings[:prefix]} "
  end

  ###########
  # CONFIGURE
  ###########

  # TODO: Remove this once PA-1607 is resolved.
  # TODO: Can we use native autoconf? The dependencies seemed a little too extensive
  pkg.configure { ["/opt/pl-build-tools/bin/autoconf"] } if platform.is_aix?

  # Here we set --enable-bundled-libyaml to ensure that the libyaml included in
  # ruby is used, even if the build system has a copy of libyaml available
  pkg.configure do
    [
      "bash configure \
        --enable-shared \
        --enable-bundled-libyaml \
        --disable-install-doc \
        --disable-install-rdoc \
        #{settings[:host]} \
        #{special_flags}"
     ]
  end

  #########
  # INSTALL
  #########
  if platform.is_windows?
    # Because the autogenerated batch wrappers for ruby built from source are
    # not consistent with legacy builds, we removed the addition of the batch
    # wrappers from the build of ruby and instead we will just put them in
    # ourselves. note that we can use the same source file for all batch wrappers
    # because the batch wrappers use the wrappers file name to find the source
    # to execute (i.e. irb.bat will look to execute "irb" due to its filename).
    #
    # Note that this step must happen before the install step below.
    pkg.install do
      %w{erb gem irb rake rdoc ri}.map do |name|
        "cp -f ../windows_ruby_gem_wrapper.bat #{settings[:ruby_bindir]}/#{name}.bat"
      end
    end
  end

  target_doubles = {
    'powerpc-ibm-aix6.1.0.0' => 'powerpc-aix6.1.0.0',
    'aarch64-redhat-linux' => 'aarch64-linux',
    'ppc64le-redhat-linux' => 'powerpc64le-linux',
    'powerpc64le-suse-linux' => 'powerpc64le-linux',
    'powerpc64le-linux-gnu' => 'powerpc64le-linux',
    's390x-linux-gnu' => 's390x-linux',
    'i386-pc-solaris2.10' => 'i386-solaris2.10',
    'sparc-sun-solaris2.10' => 'sparc-solaris2.10',
    'i386-pc-solaris2.11' => 'i386-solaris2.11',
    'sparc-sun-solaris2.11' => 'sparc-solaris2.11',
    'arm-linux-gnueabihf' => 'arm-linux-eabihf',
    'arm-linux-gnueabi' => 'arm-linux-eabi',
    'x86_64-w64-mingw32' => 'x64-mingw32',
    'i686-w64-mingw32' => 'i386-mingw32'
  }
  if target_doubles.has_key?(settings[:platform_triple])
    rbconfig_topdir = File.join(settings[:ruby_dir], 'lib', 'ruby', '2.4.0', target_doubles[settings[:platform_triple]])
  else
    rbconfig_topdir = "$$(#{settings[:ruby_bindir]}/ruby -e \"puts RbConfig::CONFIG[\\\"topdir\\\"]\")"
  end

  rbconfig_changes = {}
  if platform.is_aix?
    rbconfig_changes["CC"] = "gcc"
  elsif platform.is_cross_compiled? || platform.is_solaris?
    rbconfig_changes["CC"] = "gcc"
    rbconfig_changes["warnflags"] = "-Wall -Wextra -Wno-unused-parameter -Wno-parentheses -Wno-long-long -Wno-missing-field-initializers -Wno-tautological-compare -Wno-parentheses-equality -Wno-constant-logical-operand -Wno-self-assign -Wunused-variable -Wimplicit-int -Wpointer-arith -Wwrite-strings -Wdeclaration-after-statement -Wimplicit-function-declaration -Wdeprecated-declarations -Wno-packed-bitfield-compat -Wsuggest-attribute=noreturn -Wsuggest-attribute=format -Wno-maybe-uninitialized"
    if platform.name =~ /el-7-ppc64le/
      # EL 7 on POWER will fail with -Wl,--compress-debug-sections=zlib so this
      # will remove that entry
      rbconfig_changes["DLDFLAGS"] = "-Wl,-rpath=/opt/puppetlabs/puppet/lib -L/opt/puppetlabs/puppet/lib  -Wl,-rpath,/opt/puppetlabs/puppet/lib"
    elsif platform.name =~ /solaris-10-sparc/
      # ld on solaris 10 sparc does not understand `-Wl,-E` - this is what remains after removing it:
      rbconfig_changes["LDFLAGS"] = "-L. -Wl,-rpath=/opt/puppetlabs/puppet/lib -fstack-protector"
      # `-Wl,--compress-debug-sections=zlib` is also a problem here:
      rbconfig_changes["DLDFLAGS"] = "-Wl,-rpath=/opt/puppetlabs/puppet/lib"
    end
  elsif platform.is_windows?
    rbconfig_changes["CC"] = "x86_64-w64-mingw32-gcc"
  elsif platform.name =~ /^fedora-28/
    # Fedora 28 uses native GCC 8.0.1. When building ruby C extensions (in
    # ruby-augeas, for example) mkmf will fail when ruby 2.4.4's
    # CONFIG['warnflags'] are applied to a conftest with -Werror before
    # generating the Makefile. This patch removes a few flags from
    # CONFIG['warnflags'] that are no longer valid and ignores a few new
    # warnings generated by ruby.h.
    rbconfig_changes["warnflags"] = "-Wall -Wextra -Wno-unused-parameter -Wno-parentheses -Wno-long-long -Wno-missing-field-initializers -Wno-tautological-compare -Wunused-variable -Wimplicit-int -Wpointer-arith -Wwrite-strings -Wdeclaration-after-statement -Wimplicit-function-declaration -Wdeprecated-declarations -Wno-packed-bitfield-compat -Wsuggest-attribute=noreturn -Wsuggest-attribute=format -Wimplicit-fallthrough=0 -Wno-attributes"
  end

  unless rbconfig_changes.empty?
    pkg.install do
      [
        "#{settings[:host_ruby]} ../rbconfig-update.rb \"#{rbconfig_changes.to_s.gsub('"', '\"')}\" #{rbconfig_topdir}",
        "cp original_rbconfig.rb #{settings[:datadir]}/doc/rbconfig-2.4.4-orig.rb",
        "cp new_rbconfig.rb #{rbconfig_topdir}/rbconfig.rb",
      ]
    end
  end
end
