# Runtime Fallback Contracts

This audit covers initialization and metadata fallbacks surfaced in the
November 19–21, 2026 changes through `6cadb2a1`, together with their constructors,
lookup producers, and consumers. It also covers the related older super lookup
that those changes exposed. The rules below apply to future runtime changes.

An entry must identify the actual absence state, its producer, and the consumer's
behavior at that specific site. Age and an existing green suite are insufficient.
A description of one caller or a whole family does not certify every expression
in that family. The inventory below records contracts for the listed paths; it
is not an exhaustive certification of all fallback expressions in the repository.

## Required State

A fallback must represent a real absence state. It must not turn a violated
initialization invariant into another plausible Ruby object, class, or method.
Prefer required fields when the constructor always supplies the value. If a
shared header must permit bootstrap absence, runtime readers unwrap its
invariant instead of substituting a base class.

- Published objects have a class. Thread descriptions and Hash copies must use
  that class, preserving subclasses. Object.class is nullable for staged Class
  and Symbol bootstrap; that does not authorize class defaults on runtime objects.
- VM.prepare initializes the main thread once before evaluating Ruby. Builtins,
  worker allocation, and Fiber allocation require that prepared state. They do
  not initialize a replacement main thread when current_thread is absent.
- Both Thread constructors install main_fiber and current_fiber. Those fields
  remain required for unstarted, running, suspended, and retired Threads.
  Retirement detaches execution buffers, not the root fiber identity.
- Concrete method lookup results, cache entries, and captured method objects
  explicitly carry their definition node. Synthetic respond_to_missing? handles
  explicitly carry null and use missing-method dispatch. Source and parameter
  reflection consume implementations directly, without fabricating resolved
  lookup metadata. The unused older exact-method resolver has been removed.
- A successful concrete method lookup has a physical Ruby owner. Reflection
  obtains it without creating an ordinary object's singleton class. It must not
  substitute owner_class when an expected owner cannot be found.
- Method change hooks have registered private defaults. Explicitly removing or
  undefining one requests normal method_missing/NoMethodError behavior, not a
  silent optional-hook miss.

## Lookup Absence Is Not Missing Metadata

Super execution and defined?(super) share lookupSuperMethodFromDefinition.
Once the receiver's definition node is found, a missing successor or an
undef_method barrier is final. Neither lexical scope nor ordinary method lookup
may restart the search after that miss.

There are two distinct module binding cases:

1. A captured module owner corresponds to an inclusion node in the receiver's
   hierarchy. Super continues after that node. An exact captured node takes
   precedence over matching the visible owner.
2. An UnboundMethod from a module is bound to an unrelated hierarchy that does
   not include that module. Ruby starts super at the receiver's dispatch class.
   This is an explicit binding rule, not recovery after a successor lookup fails.

Method#super_method uses strict captured-node lookup. In particular, a rebound
method can have a working super call while its super_method is nil. Do not merge
that introspection operation into execution lookup.

## Retained Runtime Alternatives

| Area / canonical code | Actual absence or alternate state | Required interpretation |
| --- | --- | --- |
| `RegexpObject.regex` / `builtinRegexpAllocate` | `Regexp.allocate` has not compiled a pattern yet, so its native regex pointer is null. The allocator still initializes its class, binary encoding, empty source storage, and options. | Readers requiring a pattern raise `TypeError`; `encoding`, `fixed_encoding?`, and `inspect` implement the documented uninitialized behavior. `initializeRegexp` installs compiled storage and its finalizer on the same object. |
| VM.findMethod, resolveMethodForCallSite, getDispatchClass | Ordinary objects may never have a singleton class. Class/module eigenclass inheritance requires one. | Reuse existing singleton classes; materialize for class/module dispatch; otherwise use the object's actual class. A cold cache performs lookup and records complete metadata. |
| MethodEntry.original_name / original_defining_node | Ordinary definitions and aliases of local methods need no separate definition node; an inherited alias may have an implementation owned elsewhere. | Use the receiver inclusion node for a local alias. Only an inherited alias records a different origin; original_name still preserves its source name. A bare module pointer must not replace a local alias's actual inclusion node. |
| ownerClassForDefiningNode, lookupMethodAfterNode | A bare module has no including Class node. | owner_class is a class-chain search anchor, sometimes Object for a bare module. Ruby-visible ownership still comes from the actual module node. |
| MethodObject / UnboundMethodObject.defining_node | A synthetic respond_to_missing? handle has no concrete definition. | Calling it uses method_missing; super_method returns nil. Null is explicit at this producer, not a default for ordinary lookups. |
| enclosingMethodEnvironment, forwardingFrame, callSuper | A Ruby method environment survives an escaped block; an active native frame has no Ruby method environment. | Captured environments supply durable method context. Native super uses the native frame's definition node. Forwarding uses the active method's incoming block while it exists, otherwise the block captured by the executing closure. An absent forwarded block is valid. |
| CallFrame.method_name, backtrace_context.base_name | Top-level and body chunks are not named dispatched methods; some label contexts have no separate base name. | Use the chunk/context name for diagnostics. This does not invent a definition node or authorize super lookup from lexical nesting. |
| evalSourceWithEncodingAndContext | Binding eval can supply a stored label context; ordinary eval can have a Ruby caller; host/top-level eval may have neither. | Use the supplied context, otherwise the caller context where applicable, otherwise the compiler's top-level context. |
| Chunk.source_file / source_absolute_path, require_relative, backtrace locations | File chunks have a saved canonical identity; eval and inline source may have only a logical/display filename or no filename. | Preserve logical path versus canonical absolute_path. require_relative prefers saved identity, then the explicit logical source/loading context. Inline CLI programs explicitly have no canonical file identity despite their `-e` display label. Diagnostics may use a chunk name when no source filename exists. |
| publicModuleName, Class.module.classpath, Thread description | Anonymous classes/modules lack a public constant path. | Use the anonymous/display name or omit the owner qualifier. This is independent of the required Object.class pointer. |
| VM.current_thread, rootFiberForCurrentThread, threadStorageForFiber | During construction, main execution buffers are installed before the main Thread and its ownership link. | Bootstrap-safe observers may find no thread; root buffer setup uses the VM's main fiber. Ruby execution begins only after those links are installed. |
| threadBacktraceFrames, fiberLocalTarget | A running thread's live state is in the VM; suspended state is saved on its thread/fiber. | Use live VM state for the current thread and saved current_fiber for another. Worker root buffers belong to the Thread; main/ordinary Fiber buffers belong to the Fiber. Missing buffers before first use or after retirement are valid empty storage. |
| switchFiber, ensureFiberCoroutine, schedulerYield, fiberContext | Main native execution has no managed coroutine. Workers and non-root Fibers acquire coroutine storage before first execution and release it after termination. | Context selection uses a Fiber coroutine, a worker-root Thread coroutine, or the main native context. switchFiber initializes created targets; schedulerYield initializes created workers before switching. A nonexistent coroutine during cleanup means there is no resource to release. |
| Fiber.storage, Thread variables, callback collection contexts | Ruby permits absent storage; empty iterations may never need a buffer. | Allocate on first write/yield and preserve nil/empty results before allocation. Storage snapshots preserve the Hash's actual class. |
| Thread.fiber_scheduler, join/sleep deadlines, pending interrupts | No scheduler is installed, a wait is indefinite, or no interrupt is pending. | Preserve the API's nil/error/no-op result. Optional scheduler_close versus close is a protocol choice; required scheduler methods are validated when installed. |

## Semantic Defaults and Optional Results

Encoding registration captures the environment's locale charmap with a private
libc locale object before Ruby execution. If the environment names an unavailable
locale, registration retries with the C locale, matching Ruby startup behavior;
allocation failure remains fatal. The captured charmap and encoding are required
VM state. Changing ENV or the default external encoding does not recapture them.

These reviewed alternatives represent Ruby inputs/results or lazy resources,
not partially initialized interpreter metadata:

- Pack directive counts, star flags, omitted/nil output buffers, optional random
  providers, and socket level/option namespaces select API-defined behavior.
- Required conversion failures and invalid integer ranges raise Ruby errors.
  Optional conversion probes use the shared VM probe helpers and preserve their
  missing/nil distinctions; they do not inspect exception text to infer absence.
- Regexp preparation can report no match without allocating captures. Encoding
  variants, frozen-string intern entries, call-site slots, and loaded-feature
  entries can miss their caches and then be created or reused normally.
- Hash iteration can fail to find a snapshot entry because Ruby code deleted it;
  skipping that entry preserves mutation semantics. This is not a missing Hash
  implementation field.
- Exception causes/backtraces, LocalJumpError reasons, Time zone
  names, and thread names are optional Ruby state. Default messages, nil values,
  or fixed-offset formatting follow those states. An unmapped errno uses the
  standard SystemCallError class while retaining the original native errno.
- Process::Status always owns an actual wait result and PID. `Status.wait`'s
  ECHILD result deliberately has PID -1 and status 0; WNOHANG with a running
  child returns nil. No process-status reader synthesizes a missing PID.
- A rescued-exception entry created by a native scheduler-close callback has
  no Ruby rescue scope. CATCH_START always supplies its actual frame depth and
  catch range; jumps and frame exits require that metadata for Ruby rescues.
- Method mutation ownership is resolved by methodDefinitionOwner for def, alias,
  and undef. Top-level ownership comes from Object's lexical scope; instance_eval
  supplies an explicit definition target. Missing both is an internal error; the
  owner must not be guessed from self. A non-module self alone does not imply
  Object ownership. Alias and undef opcodes reuse the Module implementations for
  inherited lookup, undefined barriers, frozen checks and callback dispatch.

## Regression Evidence

The audit adds coverage for module super misses and undef barriers, detached
module bindings with defined?(super), method capture without singleton creation,
undefined instance-method hook dispatch, and shared def/alias/undef ownership
for eval, top-level, and lexical method contexts. Existing tests cover rebound
Method#super_method, escaped blocks, C-extension super, thread/fiber retirement,
unstarted worker storage, and subclass-preserving Hash/Fiber storage copying.
The thread storage test also checks the boundary between an empty VM and the
prepared main thread, and the required root of an unstarted worker.

Focused checks exercise super/Method/UnboundMethod, Thread/Fiber/Hash, forwarding,
Binding, native extensions, method hooks, synchronization, and require paths.
Run the full suite after changes to these shared invariants:

```sh
nix develop -c zig build test
```
