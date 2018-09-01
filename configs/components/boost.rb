component "boost" do |pkg, settings, platform|
  # Source-Related Metadata
  pkg.version "1.67.0"
  pkg.md5sum "4850fceb3f2222ee011d4f3ea304d2cb"
  # Apparently boost doesn't use dots to version they use underscores....arg
  pkg.url "http://downloads.sourceforge.net/project/boost/boost/#{pkg.get_version}/boost_#{pkg.get_version.gsub('.','_')}.tar.gz"
  pkg.mirror "#{settings[:buildsources_url]}/boost_#{pkg.get_version.gsub('.','_')}.tar.gz"

  if platform.is_solaris?
    pkg.apply_patch 'resources/patches/boost/0001-fix-build-for-solaris.patch'
    pkg.apply_patch 'resources/patches/boost/Fix-bootstrap-build-for-solaris-10.patch'
    pkg.apply_patch 'resources/patches/boost/force-SONAME-option-for-solaris.patch'
  end

  if platform.is_solaris? || platform.is_aix?
    pkg.apply_patch 'resources/patches/boost/solaris-aix-boost-filesystem-unique-path.patch'
  end

  if platform.is_cisco_wrlinux?
    pkg.apply_patch 'resources/patches/boost/no-fionbio.patch'
  end

  if platform.architecture == "aarch64"
    #pkg.apply_patch 'resources/patches/boost/boost-aarch64-flags.patch'
  end

  if platform.is_windows?
    pkg.apply_patch 'resources/patches/boost/windows-thread-declare-do_try_join_until-as-inline.patch'
  end

  # Build-time Configuration

  boost_libs = settings[:boost_libs] || ['atomic', 'chrono', 'container', 'date_time', 'exception', 'filesystem',
                                         'graph', 'graph_parallel', 'iostreams', 'locale', 'log', 'math',
                                         'program_options', 'random', 'regex', 'serialization', 'signals', 'system',
                                         'test', 'thread', 'timer', 'wave']
  cflags = "-fPIC -std=c99"
  cxxflags = "-std=c++11 -fPIC"

  # These are all places where windows differs from *nix. These are the default *nix settings.
  toolset = 'gcc'
  with_toolset = "--with-toolset=#{toolset}"
  boost_dir = ""
  bootstrap_suffix = ".sh"
  execute = "./"
  addtl_flags = ""
  gpp = "#{settings[:tools_root]}/bin/g++"
  b2flags = ""
  b2location = "#{settings[:prefix]}/bin/b2"
  bjamlocation = "#{settings[:prefix]}/bin/bjam"

  if platform.is_cross_compiled_linux?
    pkg.environment "PATH" => "/opt/pl-build-tools/bin:$$PATH"
    linkflags = "-Wl,-rpath=#{settings[:libdir]}"
    gpp = "/opt/pl-build-tools/bin/#{settings[:platform_triple]}-g++"
  elsif platform.is_macos?
    pkg.environment "PATH" => "/opt/pl-build-tools/bin:$$PATH"
    linkflags = ""
    gpp = "clang++"
    toolset = 'gcc'
    with_toolset = "--with-toolset=clang"
  elsif platform.is_solaris?
    pkg.environment 'PATH', '/opt/pl-build-tools/bin:/usr/sbin:/usr/bin:/usr/local/bin:/usr/ccs/bin:/usr/sfw/bin:/usr/csw/bin'
    linkflags = "-Wl,-rpath=#{settings[:libdir]},-L/opt/pl-build-tools/#{settings[:platform_triple]}/lib,-L/usr/lib"
    b2flags = "define=_XOPEN_SOURCE=600"
    if platform.architecture == "sparc"
      b2flags = "#{b2flags} instruction-set=v9"
    end
    gpp = "/opt/pl-build-tools/bin/#{settings[:platform_triple]}-g++"
  elsif platform.is_windows?
    arch = platform.architecture == "x64" ? "64" : "32"
    pkg.environment "PATH" => "C:/tools/mingw#{arch}/bin:$$PATH"
    pkg.environment "CYGWIN" => "nodosfilewarning"
    b2location = "#{settings[:prefix]}/bin/b2.exe"
    bjamlocation = "#{settings[:prefix]}/bin/bjam.exe"
    # bootstrap.bat does not take the `--with-toolset` flag
    toolset = "gcc"
    with_toolset = ""
    # we do not need to reference the .bat suffix when calling the bootstrap script
    bootstrap_suffix = ""
    # we need to make sure we link against non-cygwin libraries
    execute = "cmd.exe /c "

    gpp = "C:/tools/mingw#{arch}/bin/g++"

    # Set the address model so we only build one arch
    #
    # By default, boost gets built with WINVER set to the value for Windows XP.
    # We want it to be Vista/Server 2008
    #
    # Set layout to system to avoid nasty version numbers and arches in filenames
    b2flags = "address-model=#{arch} \
               define=WINVER=0x0600 \
               define=_WIN32_WINNT=0x0600 \
               --layout=system"

    # We don't have iconv available on windows yet
    install_only_flags = "boost.locale.iconv=off"
  elsif platform.is_aix?
    pkg.environment "PATH" => "/opt/freeware/bin:/opt/pl-build-tools/bin:$(PATH)"
    linkflags = "-Wl,-L#{settings[:libdir]},-L/opt/pl-build-tools/lib"
  else
    pkg.environment "PATH" => "#{settings[:bindir]}:$$PATH"
    linkflags = "-Wl,-rpath=#{settings[:libdir]},-rpath=#{settings[:libdir]}64"
  end

  # Set user-config.jam
  if platform.is_windows?
    userconfigjam = %Q{using gcc : : #{gpp} ;}
  else
    if platform.architecture =~ /arm|s390x/ || platform.is_aix?
      userconfigjam = %Q{using gcc : 5.2.0 : #{gpp} : <linkflags>"#{linkflags}" <cflags>"#{cflags}" <cxxflags>"#{cxxflags}" ;}
    else
      userconfigjam = %Q{using gcc : 4.8.2 : #{gpp} : <linkflags>"#{linkflags}" <cflags>"#{cflags}" <cxxflags>"#{cxxflags}" ;}
    end
  end

  # Build Commands

  # On some platforms, we have multiple means of specifying paths. Sometimes, we need to use either one
  # form or another. `special_prefix` allows us to do this. i.e., on windows, we need to have the
  # windows specific path (C:/), whereas for everything else, we can default to the drive root currently
  # in use (/cygdrive/c). This has to do with how the program is built, where it is expecting to find
  # libraries and binaries, and how it tries to find them.
  pkg.build do
    [
      %Q{echo '#{userconfigjam}' > ~/user-config.jam},
      "cd tools/build",
      "#{execute}bootstrap#{bootstrap_suffix} #{with_toolset}",
      "./b2 \
      install \
      variant=release \
      link=shared \
      toolset=#{toolset} \
      #{b2flags} \
      -d+2 \
      --prefix=#{settings[:prefix]} \
      --debug-configuration"
    ]
  end

  pkg.install do
    [
      "#{b2location} \
      install \
      variant=release \
      link=shared \
      toolset=#{toolset} \
      #{b2flags} \
      -d+2 \
      --debug-configuration \
      --prefix=#{settings[:prefix]} \
      --build-dir=. \
      #{boost_libs.map {|lib| "--with-#{lib}"}.join(" ")} \
      #{install_only_flags}",
      "chmod 0644 #{settings[:includedir]}/boost/graph/vf2_sub_graph_iso.hpp",
      "chmod 0644 #{settings[:includedir]}/boost/thread/v2/shared_mutex.hpp",
      # Remove extraneous Boost.Build stuff:
      "rm -f ~/user-config.jam",
      "rm -rf #{settings[:prefix]}/share/boost-build",
      "rm -f #{b2location}",
      "rm -f #{bjamlocation}",
    ]
  end

  # Boost.Build's behavior around setting the install_name for dylibs on macOS
  # is not easily configurable. By default, it will hard-code the relative build
  # directory there, making the libraries unusable once they're moved to the
  # puppet libdir. Instead of dealing with this in a jamfile somewhere, we'll
  # use a script to manually rewrite the finshed dylibs' install_names to use
  # @rpath instead of the build directory.
  if platform.is_macos?
    pkg.add_source("file://resources/files/boost/macos_rpath_install_names.erb")
    pkg.configure do
      [
        "#{settings[:bindir]}/erb libdir=#{settings[:libdir]} ../macos_rpath_install_names.erb > macos_rpath_install_names.sh",
        "chmod +x macos_rpath_install_names.sh",
      ]
    end
    pkg.install do
      [
        "./macos_rpath_install_names.sh",
      ]
    end
  end
end
