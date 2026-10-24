// Isolated LLVM ORC executor. Cache relocatable objects, never linked addresses.
#include "llvm/ADT/StringExtras.h"
#include "llvm/Config/llvm-config.h"
#include "llvm/ExecutionEngine/ObjectCache.h"
#include "llvm/ExecutionEngine/Orc/CompileUtils.h"
#include "llvm/ExecutionEngine/Orc/ExecutionUtils.h"
#include "llvm/ExecutionEngine/Orc/LLJIT.h"
#include "llvm/IR/Verifier.h"
#include "llvm/IRReader/IRReader.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/SHA256.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Support/raw_ostream.h"
#include <cstdlib>

#ifndef LG_ORC_BUILD_ID
#error "Build with checks/build-orc-runner.sh"
#endif
using namespace llvm;
using namespace llvm::orc;

static std::string env(const char *name, const char *fallback = "") {
  const char *v = std::getenv(name);
  return v && *v ? v : fallback;
}
static std::string digest(StringRef bytes) {
  return toHex(SHA256::hash(arrayRefFromStringRef(bytes)), true);
}
static int fail(Error e) {
  errs() << "orc: " << toString(std::move(e)) << '\n';
  return 1;
}

class DiskCache final : public ObjectCache {
  std::string tag, path;
  bool enabled;
  std::unique_ptr<MemoryBuffer> cached;
public:
  unsigned hits = 0, misses = 0, writes = 0, invalid = 0;
  DiskCache(std::string tag, std::string path, bool enabled)
      : tag(std::move(tag)), path(std::move(path)), enabled(enabled) {
    if (!enabled) return;
    auto file = MemoryBuffer::getFile(this->path);
    if (!file) return;
    StringRef bytes = (*file)->getBuffer();
    // One atomic file contains format, payload digest, and object bytes.
    if (bytes.size() > 72 && bytes.take_front(7) == "LGORC1\n" &&
        bytes[71] == '\n' && bytes.slice(7, 71) == digest(bytes.drop_front(72)))
      cached = MemoryBuffer::getMemBufferCopy(bytes.drop_front(72), "cached object");
    else ++invalid;
  }
  std::unique_ptr<MemoryBuffer> getObject(const Module *m) override {
    // ORC platform helpers also pass through this callback. Never cache them
    // under the submitted program's identity.
    if (m->getModuleIdentifier() != tag) return nullptr;
    if (cached) {
      ++hits;
      return MemoryBuffer::getMemBufferCopy(cached->getBuffer(), "cached object");
    }
    ++misses;
    return nullptr;
  }
  void notifyObjectCompiled(const Module *m, MemoryBufferRef object) override {
    if (!enabled || m->getModuleIdentifier() != tag) return;
    int fd;
    SmallString<256> tmp;
    if (auto ec = sys::fs::createUniqueFile(path + ".tmp-%%%%%%", fd, tmp)) {
      errs() << "orc-cache: cannot write: " << ec.message() << '\n';
      return;
    }
    raw_fd_ostream out(fd, true);
    out << "LGORC1\n" << digest(object.getBuffer()) << '\n' << object.getBuffer();
    out.close();
    if (out.has_error()) {
      out.clear_error();
      sys::fs::remove(tmp);
      errs() << "orc-cache: object write failed\n";
      return;
    }
    if (auto ec = sys::fs::rename(tmp, path)) {
      sys::fs::remove(tmp);
      errs() << "orc-cache: publish failed: " << ec.message() << '\n';
      return;
    }
    ++writes;
  }
};

int main(int argc, char **argv) {
  if (argc < 2) {
    errs() << "usage: orc-runner module.bc [program args...]\n";
    return 2;
  }
  std::string level = env("LW_ORC_OPT_LEVEL", "2");
  if (level.size() != 1 || level[0] < '0' || level[0] > '3') {
    errs() << "orc: LW_ORC_OPT_LEVEL must be 0, 1, 2 or 3\n";
    return 2;
  }
  auto input = MemoryBuffer::getFile(argv[1]);
  if (!input) { errs() << "orc: " << input.getError().message() << '\n'; return 1; }
  auto context = std::make_unique<LLVMContext>();
  SMDiagnostic diagnostic;
  auto module = parseIR((*input)->getMemBufferRef(), diagnostic, *context);
  if (!module) { diagnostic.print("orc", errs()); return 1; }
  if (verifyModule(*module, &errs())) return 1;
  auto *main = module->getFunction("main");
  bool noArgs = main && main->arg_empty();
  if (!main || main->isDeclaration() || main->hasLocalLinkage() || main->isVarArg() ||
      main->getCallingConv() != CallingConv::C || !main->getReturnType()->isIntegerTy(32) ||
      (!noArgs && (main->arg_size() != 2 ||
                  !main->getArg(0)->getType()->isIntegerTy(32) ||
                  !main->getArg(1)->getType()->isPointerTy() ||
                  main->getArg(1)->getType()->getPointerAddressSpace() != 0))) {
    errs() << "orc: main must define a C ABI i32 function with () or (i32, ptr) parameters\n";
    return 1;
  }

  InitializeNativeTarget();
  InitializeNativeTargetAsmPrinter();
  InitializeNativeTargetAsmParser();
  auto target = JITTargetMachineBuilder::detectHost();
  if (!target) return fail(target.takeError());
  target->setRelocationModel(Reloc::PIC_);
  target->setCodeModel(CodeModel::Small);
  target->setCodeGenOptLevel(static_cast<CodeGenOptLevel>(level[0] - '0'));
  auto machine = target->createTargetMachine();
  if (!machine) return fail(machine.takeError());
  auto layout = (*machine)->createDataLayout();
  const auto &triple = module->getTargetTriple();
  const auto &host = target->getTargetTriple();
  // Clang spells the host arm64-apple-macosx*, detectHost uses *-darwin*.
  bool sameOS = triple.getOS() == host.getOS() || (triple.isMacOSX() && host.isMacOSX());
  if (!triple.str().empty() &&
      (triple.getArch() != host.getArch() || !sameOS ||
       triple.getEnvironment() != host.getEnvironment() ||
       triple.getObjectFormat() != host.getObjectFormat())) {
    errs() << "orc: incompatible target triple " << triple.str() << " (host " << host.str() << ")\n";
    return 1;
  }
  if (!module->getDataLayoutStr().empty() && module->getDataLayout() != layout) {
    errs() << "orc: incompatible data layout\n";
    return 1;
  }
  module->setTargetTriple(host);
  module->setDataLayout(layout);
  std::string identity = std::string("lg-orc-v1\n") + LG_ORC_BUILD_ID + "\n" +
      LLVM_VERSION_STRING + "\n" + host.str() + "\n" + target->getCPU() + "\n" +
      target->getFeatures().getString() + "\n" + layout.getStringRepresentation() +
      "\nreloc=PIC;code=small;pipeline=default;opt=" + level + "\n" +
      digest((*input)->getBuffer());
  std::string key = digest(identity), tag = "lg-orc-program:" + key;
  bool enabled = env("LW_ORC_CACHE", "1") != "0";
  std::string dir = env("LW_ORC_CACHE_DIR", "src/.orc");
  if (enabled) {
    if (auto ec = sys::fs::create_directories(dir)) {
      errs() << "orc-cache: unavailable: " << ec.message() << '\n';
      enabled = false;
    }
  }
  // Declared before JIT: cache survives compiler callbacks and JIT teardown.
  DiskCache cache(tag, dir + "/" + key + ".objcache", enabled);
  module->setModuleIdentifier(tag);
  // ORC advertises symbols from this IR before asking the object cache. Cold
  // and warm inputs must receive identical optimization (e.g. dead linkonce
  // definitions must not be advertised when the cached object omits them).
  if (level != "0") {
    LoopAnalysisManager lam;
    FunctionAnalysisManager fam;
    CGSCCAnalysisManager cgam;
    ModuleAnalysisManager mam;
    PassBuilder passes(machine->get());
    passes.registerModuleAnalyses(mam);
    passes.registerCGSCCAnalyses(cgam);
    passes.registerFunctionAnalyses(fam);
    passes.registerLoopAnalyses(lam);
    passes.crossRegisterProxies(lam, fam, cgam, mam);
    auto opt = level == "1" ? OptimizationLevel::O1 :
               level == "2" ? OptimizationLevel::O2 : OptimizationLevel::O3;
    auto pipeline = passes.buildPerModuleDefaultPipeline(opt);
    pipeline.run(*module, mam);
  }
  auto jit = LLJITBuilder().setJITTargetMachineBuilder(std::move(*target))
      .setCompileFunctionCreator([&cache](JITTargetMachineBuilder builder)
          -> Expected<std::unique_ptr<IRCompileLayer::IRCompiler>> {
        return std::make_unique<ConcurrentIRCompiler>(std::move(builder), &cache);
      }).create();
  if (!jit) return fail(jit.takeError());
  // LLJIT's default process-symbol library follows its platform overrides.
  // A generator on the main library would shadow __cxa_atexit and register
  // JIT destructors with libc, after their executable memory has been freed.
  if (auto e = (*jit)->addIRModule(ThreadSafeModule(std::move(module), std::move(context))))
    return fail(std::move(e));
  if (auto e = (*jit)->initialize((*jit)->getMainJITDylib())) return fail(std::move(e));
  auto entry = (*jit)->lookup("main");
  if (!entry) return fail(entry.takeError());
  // input.bc is argv[0]; the original program remains argv[1].
  int status = noArgs ? entry->toPtr<int (*)()>()() :
      entry->toPtr<int (*)(int, char **)>()(argc - 1, argv + 1);
  if (auto e = (*jit)->deinitialize((*jit)->getMainJITDylib())) return fail(std::move(e));
  if (env("LW_ORC_STATS") == "1")
    errs() << "orc-cache hits=" << cache.hits << " misses=" << cache.misses
           << " writes=" << cache.writes << " invalid=" << cache.invalid << '\n';
  return status;
}
