class CodesignRequirement < Requirement
  include FileUtils
  fatal true

  satisfy(:build_env => false) do
    mktemp do
      touch "llvm_check.txt"
      quiet_system "/usr/bin/codesign", "-s", "lldb_codesign", "llvm_check.txt"
    end
  end

  def message
    <<-EOS.undent
      lldb_codesign identity must be available to build with LLDB.
      See: https://llvm.org/svn/llvm-project/lldb/trunk/docs/code-signing.txt
    EOS
  end
end

class Llvm < Formula
  desc "llvm (Low Level Virtual Machine): a next-gen compiler infrastructure"
  homepage "http://llvm.org/"

  stable do
    url "http://llvm.org/releases/3.6.2/llvm-3.6.2.src.tar.xz"
    sha256 "f60dc158bfda6822de167e87275848969f0558b3134892ff54fced87e4667b94"

    resource "clang" do
      url "http://llvm.org/releases/3.6.2/cfe-3.6.2.src.tar.xz"
      sha256 "ae9180466a23acb426d12444d866b266ff2289b266064d362462e44f8d4699f3"
    end

    resource "libcxx" do
      url "http://llvm.org/releases/3.6.2/libcxx-3.6.2.src.tar.xz"
      sha256 "52f3d452f48209c9df1792158fdbd7f3e98ed9bca8ebb51fcd524f67437c8b81"
    end

    resource "lld" do
      url "http://llvm.org/releases/3.6.2/lld-3.6.2.src.tar.xz"
      sha256 "43f553c115563600577764262f1f2fac3740f0c639750f81e125963c90030b33"
    end

    resource "lldb" do
      url "http://llvm.org/releases/3.6.2/lldb-3.6.2.src.tar.xz"
      sha256 "940dc96b64919b7dbf32c37e0e1d1fc88cc18e1d4b3acf1e7dfe5a46eb6523a9"
    end

    resource "clang-tools-extra" do
      url "http://llvm.org/releases/3.6.2/clang-tools-extra-3.6.2.src.tar.xz"
      sha256 "6a0ec627d398f501ddf347060f7a2ccea4802b2494f1d4fd7bda3e0442d04feb"
    end
  end

  bottle do
    revision 1
    sha256 "54c815d99473ef948bee29b577315461a140117b874396fda617a5c7d1bdbb0b" => :yosemite
    sha256 "2be603591104a91d0a16ba5a6231717d5252ef860e83af620fbc5d10394fcb61" => :mavericks
    sha256 "3996bbf655ae2c8457304f41d2c3df0b96f307f9fb624417c76afa75d3b587c0" => :mountain_lion
  end

  head do
    url "http://llvm.org/git/llvm.git"

    resource "clang" do
      url "http://llvm.org/git/clang.git"
    end

    resource "libcxx" do
      url "http://llvm.org/git/libcxx.git"
    end

    resource "lld" do
      url "http://llvm.org/git/lld.git"
    end

    resource "lldb" do
      url "http://llvm.org/git/lldb.git"
    end

    resource "clang-tools-extra" do
      url "http://llvm.org/git/clang-tools-extra.git"
    end
  end

  option :universal
  option "with-clang", "Build Clang support library"
  option "with-lld", "Build LLD linker"
  option "with-lldb", "Build LLDB debugger"
  option "with-rtti", "Build with C++ RTTI"
  option "with-python", "Build Python bindings against Homebrew Python"
  option "without-assertions", "Speeds up LLVM, but provides less debug information"

  deprecated_option "rtti" => "with-rtti"
  deprecated_option "disable-assertions" => "without-assertions"

  if MacOS.version <= :snow_leopard
    depends_on :python
  else
    depends_on :python => :optional
  end
  depends_on "cmake" => :build

  if build.with? "lldb"
    depends_on "swig"
    depends_on CodesignRequirement
  end

  keg_only :provided_by_osx

  # Apple's libstdc++ is too old to build LLVM
  fails_with :gcc
  fails_with :llvm

  def install
    # Apple's libstdc++ is too old to build LLVM
    ENV.libcxx if ENV.compiler == :clang

    if build.with?("lldb") && build.without?("clang")
      raise "Building LLDB needs Clang support library."
    end

    if build.with? "clang"
      (buildpath/"projects/libcxx").install resource("libcxx")
      (buildpath/"tools/clang").install resource("clang")
      (buildpath/"tools/clang/tools/extra").install resource("clang-tools-extra")
    end

    (buildpath/"tools/lld").install resource("lld") if build.with? "lld"
    (buildpath/"tools/lldb").install resource("lldb") if build.with? "lldb"

    args = %w[
      -DLLVM_OPTIMIZED_TABLEGEN=On
    ]

    args << "-DLLVM_ENABLE_RTTI=On" if build.with? "rtti"

    if build.with? "assertions"
      args << "-DLLVM_ENABLE_ASSERTIONS=On"
    else
      args << "-DCMAKE_CXX_FLAGS_RELEASE='-DNDEBUG'"
    end

    if build.universal?
      ENV.permit_arch_flags
      args << "-DCMAKE_OSX_ARCHITECTURES=#{Hardware::CPU.universal_archs.as_cmake_arch_flags}"
    end

    mktemp do
      system "cmake", "-G", "Unix Makefiles", buildpath, *(std_cmake_args + args)
      system "make"
      system "make", "install"
    end

    if build.with? "clang"
      system "make", "-C", "projects/libcxx", "install",
        "DSTROOT=#{prefix}", "SYMROOT=#{buildpath}/projects/libcxx"

      (share/"clang/tools").install Dir["tools/clang/tools/scan-{build,view}"]
      inreplace "#{share}/clang/tools/scan-build/scan-build", "$RealBin/bin/clang", "#{bin}/clang"
      bin.install_symlink share/"clang/tools/scan-build/scan-build", share/"clang/tools/scan-view/scan-view"
      man1.install_symlink share/"clang/tools/scan-build/scan-build.1"
    end

    # install llvm python bindings
    (lib/"python2.7/site-packages").install buildpath/"bindings/python/llvm"
    (lib/"python2.7/site-packages").install buildpath/"tools/clang/bindings/python/clang" if build.with? "clang"
  end

  def caveats
    <<-EOS.undent
      LLVM executables are installed in #{opt_bin}.
      Extra tools are installed in #{opt_share}/llvm.
    EOS
  end

  test do
    system "#{bin}/llvm-config", "--version"
  end
end
