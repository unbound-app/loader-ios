#import "NativePluginBridge.h"

#import <dlfcn.h>
#import <mach/mach.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

#import <algorithm>
#import <atomic>
#import <cstdint>
#import <cstring>
#import <functional>
#import <exception>
#import <memory>
#import <mutex>
#import <sstream>
#import <stdexcept>
#import <string>
#import <thread>
#import <unordered_map>
#import <vector>

#import "JSI.h"
#import "Logger.h"
#import "NativePluginFFI.h"

using namespace facebook;
using namespace facebook::jsi;

@interface NSObject (RuntimeExecutor)
- (void)callFunctionOnBufferedRuntimeExecutor:
    (std::function<void(facebook::jsi::Runtime &)> &&)executor;
@end

@interface NSObject (FabricHost)
- (id)createSurfaceWithModuleName:(NSString *)moduleName
                              mode:(NSInteger)mode
                 initialProperties:(NSDictionary *)properties;
@end

@interface FabricContainer : UIView
@property(nonatomic, weak) UIView *surfaceView;
- (void)setFabricFrame:(CGRect)frame;
@end

@implementation FabricContainer

{
    BOOL _fabricFrameProtected;
    BOOL _fabricSettingFrame;
}

- (void)setFrame:(CGRect)frame
{
    if (_fabricFrameProtected && !_fabricSettingFrame)
    {
        return;
    }
    [super setFrame:frame];
}

- (void)setFabricFrame:(CGRect)frame
{
    _fabricFrameProtected = YES;
    _fabricSettingFrame = YES;
    [super setFrame:frame];
    _fabricSettingFrame = NO;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    UIView *surfaceView = self.surfaceView;
    if (surfaceView)
    {
        surfaceView.frame = self.bounds;
        surfaceView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
}

@end

namespace {

class ObjCHandleHost final : public HostObject
{
public:
    explicit ObjCHandleHost(id value) : value_(value) {}

    id value(void) const
    {
        return value_;
    }

private:
    __strong id value_;
};

class FabricSurfaceHost final : public HostObject
{
public:
    FabricSurfaceHost(void) = default;

    void setSurface(id surface, UIView *containerView, UIView *surfaceView)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        surface_ = surface;
        view_ = containerView;
        surfaceView_ = surfaceView;
        active_ = true;
    }

    id surface(void) const
    {
        std::lock_guard<std::mutex> lock(mutex_);
        return surface_;
    }

    UIView *view(void) const
    {
        std::lock_guard<std::mutex> lock(mutex_);
        return view_;
    }

    UIView *surfaceView(void) const
    {
        std::lock_guard<std::mutex> lock(mutex_);
        return surfaceView_;
    }

    bool active(void) const
    {
        std::lock_guard<std::mutex> lock(mutex_);
        return active_;
    }

    void clear(void)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        surface_ = nil;
        view_ = nil;
        surfaceView_ = nil;
        active_ = false;
    }

private:
    mutable std::mutex mutex_;
    __strong id surface_ = nil;
    __strong UIView *view_ = nil;
    __strong UIView *surfaceView_ = nil;
    bool active_ = false;
};

class PointerHost final : public HostObject
{
public:
    explicit PointerHost(void *value) : value_(value) {}

    void *value(void) const
    {
        return value_;
    }

private:
    void *value_;
};

static Value structFields(Runtime &runtime, NSString *name, NSValue *value);

class StructHost final : public HostObject
{
public:
    StructHost(NSString *name, NSValue *value) : name_([name copy]), value_(value) {}

    Value get(Runtime &runtime, const PropNameID &name) override;

    NSString *name(void) const
    {
        return name_;
    }

    NSValue *value(void) const
    {
        return value_;
    }

private:
    NSString *name_;
    NSValue *value_;
};

class AssociationKeyHost final : public HostObject
{
public:
    explicit AssociationKeyHost(id value) : value_(value) {}

    const void *key(void) const
    {
        return (__bridge const void *) value_;
    }

private:
    __strong id value_;
};

struct FFITypeDefinition {
    ffi_type type{};
    std::vector<ffi_type *> elements;
};

struct FFITypeSpec {
    std::string name;
    ffi_type *type;
};

struct FFISignature {
    FFITypeSpec result;
    std::vector<FFITypeSpec> arguments;
};

struct FFICallArgument {
    std::vector<uint8_t> bytes;
    std::string string;
    id object;
    void *pointer;
};

struct HookSignature {
    FFITypeSpec result;
    std::vector<FFITypeSpec> arguments;
    ffi_cif cif{};
};

struct HookState;
struct HookDispatcher;

struct HookDispatcher {
    Class cls;
    SEL selector;
    IMP original;
    std::shared_ptr<HookSignature> signature;
    ffi_closure *closure = nullptr;
    void *code = nullptr;
    std::vector<std::shared_ptr<HookState>> hooks;
    std::atomic_uint activeCalls{0};
    std::atomic_bool retired{false};
    std::atomic_bool closureReleased{false};
};

struct HookState {
    uint64_t identifier;
    std::shared_ptr<Function> before;
    std::shared_ptr<Function> after;
    std::shared_ptr<Function> replace;
    std::weak_ptr<HookDispatcher> dispatcher;
    __strong id instanceTarget = nil;
    std::mutex returnCacheMutex;
    __strong NSMutableDictionary<NSArray *, NSData *> *returnCache = [NSMutableDictionary dictionary];
    bool cacheOnly = false;
    bool once = false;
    std::atomic_bool active{true};
};

class HookTokenHost final : public HostObject
{
public:
    explicit HookTokenHost(std::shared_ptr<HookState> state) : state_(std::move(state)) {}

    std::shared_ptr<HookState> state(void) const
    {
        return state_;
    }

    Value get(Runtime &runtime, const PropNameID &name) override;

private:
    std::shared_ptr<HookState> state_;
};

static std::mutex gHookMutex;
static std::unordered_map<std::string, std::shared_ptr<HookDispatcher>> gDispatchers;
static std::atomic_uint64_t gNextHookIdentifier{1};
static __weak id gRuntimeExecutorInstance = nil;
static __weak id gFabricHostInstance = nil;
static Runtime *gNativePluginRuntime = nullptr;
static std::thread::id gNativePluginRuntimeThread;

static FFITypeSpec ffiType(Runtime &runtime, const std::string &name);
static ffi_cif prepareFFICif(Runtime &runtime, const FFITypeSpec &result,
                             const std::vector<FFITypeSpec> &arguments);
static Value ffiResult(Runtime &runtime, const FFITypeSpec &spec, const std::vector<uint8_t> &bytes);
static void releaseHookClosure(const std::shared_ptr<HookDispatcher> &dispatcher);
static void dispatchFFIHook(ffi_cif *cif, void *returnValue, void **arguments, void *userData);
static void dispatchFFIHookBody(ffi_cif *cif, void *returnValue, void **arguments, void *userData);
static void dispatchVoidHook(id object, SEL selector);
static CGSize dispatchCGSizeHook(id object, SEL selector, CGSize size);
static CGSize dispatchCGSizePriorityHook(id object, SEL selector, CGSize size, float horizontal,
                                        float vertical);
static CGSize dispatchCGSizeDoublePriorityHook(id object, SEL selector, CGSize size, double horizontal,
                                               double vertical);
static CGRect dispatchCGRectObjectHook(id object, SEL selector, id indexPath);
static double dispatchDoubleObjectObjectHook(id object, SEL selector, id tableView, id indexPath);
static void dispatchVoidObjectHook(id object, SEL selector, id value);
static void dispatchVoidObjectObjectHook(id object, SEL selector, id first, id second);
static void dispatchVoidObjectObjectObjectHook(id object, SEL selector, id tableView, id cell,
                                               id indexPath);
static Value makeHook(Runtime &runtime, const Value *args, size_t count);
static void invokeHookOriginal(const std::shared_ptr<HookDispatcher> &dispatcher, void **arguments,
                               void *returnValue);
static const char *structEncoding(const std::string &name);
static void setHookReturnCache(Runtime &runtime, const std::shared_ptr<HookState> &state,
                               const Value *args, size_t count);
static void removeHookReturnCache(Runtime &runtime, const std::shared_ptr<HookState> &state,
                                  const Value *args, size_t count);
static void clearHookReturnCache(const std::shared_ptr<HookState> &state);

static std::mutex gFFIMutex;
static std::unordered_map<std::string, std::shared_ptr<FFITypeDefinition>> gFFITypes;
struct CachedFFICif {
    ffi_cif cif{};
    std::vector<ffi_type *> arguments;
};

static std::mutex gFFICifMutex;
static std::unordered_map<std::string, std::shared_ptr<CachedFFICif>> gFFICifs;

static Value makeFunction(const char *name, unsigned int argCount, Runtime &runtime,
                          const HostFunctionType &handler)
{
    return [JSI makeFunction:name argCount:argCount runtime:runtime handler:handler];
}

static Value makeFunction(const char *name, unsigned int argCount, Runtime &runtime,
                          Value (*handler)(Runtime &, const Value *, size_t))
{
    return [JSI makeFunction:name
                    argCount:argCount
                     runtime:runtime
                     handler:[handler](Runtime &rt, const Value &, const Value *args,
                                       size_t count) -> Value { return handler(rt, args, count); }];
}

static std::string hookKey(Class cls, SEL selector)
{
    return std::string(class_getName(cls)) + ":" + sel_getName(selector);
}

static bool isExecutableAddress(void *address)
{
    if (!address)
    {
        return false;
    }

    vm_address_t region = reinterpret_cast<vm_address_t>(address);
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info{};
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    kern_return_t result = vm_region_64(
        mach_task_self(), &region, &size, VM_REGION_BASIC_INFO_64,
        reinterpret_cast<vm_region_info_t>(&info), &count, &object);
    if (object != MACH_PORT_NULL)
    {
        mach_port_deallocate(mach_task_self(), object);
    }
    return result == KERN_SUCCESS && (info.protection & VM_PROT_EXECUTE) != 0;
}

static char normalizedType(const char *type)
{
    if (!type)
    {
        return '\0';
    }

    while (*type && strchr("rnNoORV", *type))
    {
        type++;
    }

    return *type;
}

static std::shared_ptr<ObjCHandleHost> objcHost(Runtime &runtime, const Value &value)
{
    if (!value.isObject())
    {
        return nullptr;
    }

    Object object = value.asObject(runtime);
    if (!object.isHostObject<ObjCHandleHost>(runtime))
    {
        return nullptr;
    }

    return object.getHostObject<ObjCHandleHost>(runtime);
}

static id objcValue(Runtime &runtime, const Value &value)
{
    std::shared_ptr<ObjCHandleHost> host = objcHost(runtime, value);
    return host ? host->value() : nil;
}

static Value pointerResult(Runtime &runtime, void *pointer)
{
    if (!pointer)
    {
        return Value::null();
    }

    return Object::createFromHostObject(runtime, std::make_shared<PointerHost>(pointer));
}

static Value objcResult(Runtime &runtime, id value)
{
    if (!value)
    {
        return Value::null();
    }

    if ([value isKindOfClass:[NSString class]])
    {
        return [JSI fromObjC:value runtime:runtime];
    }

    if ([value isKindOfClass:[NSNumber class]])
    {
        return [JSI fromObjC:value runtime:runtime];
    }

    if ([value isKindOfClass:[NSArray class]])
    {
        NSArray *array = (NSArray *) value;
        Array result(runtime, array.count);
        for (NSUInteger index = 0; index < array.count; index++)
        {
            result.setValueAtIndex(runtime, index, objcResult(runtime, array[index]));
        }
        return result;
    }

    if ([value isKindOfClass:[NSDictionary class]])
    {
        NSDictionary *dictionary = (NSDictionary *) value;
        Object result(runtime);
        for (id key in dictionary)
        {
            if (![key isKindOfClass:[NSString class]])
            {
                continue;
            }
            result.setProperty(runtime, ((NSString *) key).UTF8String,
                               objcResult(runtime, dictionary[key]));
        }
        return result;
    }

    return Object::createFromHostObject(runtime, std::make_shared<ObjCHandleHost>(value));
}

static id valueToObjC(Runtime &runtime, const Value &value)
{
    if (value.isNull() || value.isUndefined())
    {
        return [NSNull null];
    }

    if (value.isString())
    {
        NSString *string = [JSI toNSString:value runtime:runtime];
        return string ?: @"";
    }

    if (value.isBool())
    {
        return @(value.getBool());
    }

    if (value.isNumber())
    {
        return @(value.getNumber());
    }

    if (value.isBigInt())
    {
        BigInt bigint = value.asBigInt(runtime);
        if (runtime.bigintIsInt64(bigint))
        {
            return @((long long) runtime.truncate(bigint));
        }

        return @((unsigned long long) runtime.truncate(bigint));
    }

    if (!value.isObject())
    {
        return [NSNull null];
    }

    Object object = value.asObject(runtime);
    if (std::shared_ptr<ObjCHandleHost> host = objcHost(runtime, value))
    {
        return host->value();
    }

    if (object.isHostObject<StructHost>(runtime))
    {
        return object.getHostObject<StructHost>(runtime)->value();
    }

    if (object.isHostObject<PointerHost>(runtime))
    {
        return [NSValue valueWithPointer:object.getHostObject<PointerHost>(runtime)->value()];
    }

    if (object.isArray(runtime))
    {
        Array array = object.asArray(runtime);
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:array.size(runtime)];
        for (size_t index = 0; index < array.size(runtime); index++)
        {
            [result addObject:valueToObjC(runtime, array.getValueAtIndex(runtime, index)) ?: [NSNull null]];
        }
        return result;
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    Array names = object.getPropertyNames(runtime);
    for (size_t index = 0; index < names.size(runtime); index++)
    {
        Value name = names.getValueAtIndex(runtime, index);
        if (!name.isString())
        {
            continue;
        }

        NSString *key = [JSI toNSString:name runtime:runtime];
        if (key.length == 0)
        {
            continue;
        }

        id item = valueToObjC(runtime, object.getProperty(runtime, key.UTF8String));
        result[key] = item ?: [NSNull null];
    }
    return result;
}

static void executeMainSynchronously(std::function<void(void)> callback)
{
    if ([NSThread isMainThread])
    {
        callback();
        return;
    }

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block std::exception_ptr failure;
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool
        {
            try
            {
                callback();
            }
            catch (...)
            {
                failure = std::current_exception();
            }
            dispatch_semaphore_signal(semaphore);
        }
    });

    if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) != 0)
    {
        throw std::runtime_error("Native Fabric operation timed out on the main thread");
    }

    if (failure)
    {
        std::rethrow_exception(failure);
    }
}

static std::shared_ptr<FabricSurfaceHost> fabricSurfaceHost(Runtime &runtime, const Value &value)
{
    if (!value.isObject())
    {
        throw JSError(runtime, "fabric surface handle is invalid");
    }

    Object object = value.asObject(runtime);
    if (!object.isHostObject<FabricSurfaceHost>(runtime))
    {
        throw JSError(runtime, "fabric surface handle is invalid");
    }

    return object.getHostObject<FabricSurfaceHost>(runtime);
}

static NSDictionary *fabricProperties(Runtime &runtime, const Value *value)
{
    if (!value || value->isNull() || value->isUndefined())
    {
        return @{};
    }

    id object = valueToObjC(runtime, *value);
    if (![object isKindOfClass:[NSDictionary class]])
    {
        throw JSError(runtime, "fabric surface properties must be an object");
    }

    return object;
}

static double fabricNumber(Runtime &runtime, Object &object, const char *name)
{
    Value value = object.getProperty(runtime, name);
    if (!value.isNumber())
    {
        throw JSError(runtime, "fabric dimensions must be numbers");
    }
    return value.asNumber();
}

static CGSize fabricSize(Runtime &runtime, const Value &value)
{
    if (!value.isObject())
    {
        throw JSError(runtime, "fabric size must be an object");
    }

    Object object = value.asObject(runtime);
    return CGSizeMake(fabricNumber(runtime, object, "width"),
                      fabricNumber(runtime, object, "height"));
}

static CGRect fabricFrame(Runtime &runtime, const Value &value)
{
    if (!value.isObject())
    {
        throw JSError(runtime, "fabric frame must be an object");
    }

    Object object = value.asObject(runtime);
    return CGRectMake(fabricNumber(runtime, object, "x"), fabricNumber(runtime, object, "y"),
                      fabricNumber(runtime, object, "width"),
                      fabricNumber(runtime, object, "height"));
}

static void fabricStart(id surface)
{
    using Function = void (*)(id, SEL);
    ((Function)objc_msgSend)(surface, @selector(start));
}

static void fabricStop(id surface)
{
    using Function = void (*)(id, SEL);
    ((Function)objc_msgSend)(surface, @selector(stop));
}

static UIView *fabricView(id surface)
{
    using Function = UIView *(*)(id, SEL);
    return ((Function)objc_msgSend)(surface, @selector(view));
}

static void fabricSetProps(id surface, NSDictionary *properties)
{
    using Function = void (*)(id, SEL, NSDictionary *);
    ((Function)objc_msgSend)(surface, @selector(setProps:), properties);
}

static void fabricSetMinimumSize(id surface, CGSize minimumSize, CGSize maximumSize)
{
    using Function = void (*)(id, SEL, CGSize, CGSize);
    ((Function)objc_msgSend)(surface, @selector(setMinimumSize:maximumSize:), minimumSize,
                             maximumSize);
}

static Value fabricMount(Runtime &runtime, const Value *args, size_t count)
{
    if (count < 2 || !args[1].isString())
    {
        throw JSError(runtime, "fabric.mount expects a container and module name");
    }

    id container = objcValue(runtime, args[0]);
    if (![container isKindOfClass:[UIView class]])
    {
        throw JSError(runtime, "fabric.mount expects a UIView container");
    }

    id host = gFabricHostInstance;
    if (!host)
    {
        throw JSError(runtime, "Fabric host is unavailable");
    }

    NSString *moduleName = [JSI toNSString:args[1] runtime:runtime];
    NSDictionary *properties = fabricProperties(runtime, count > 2 ? &args[2] : nullptr);
    auto surfaceHost = std::make_shared<FabricSurfaceHost>();

    executeMainSynchronously([host, container, moduleName, properties, surfaceHost]() {
        if (![host respondsToSelector:@selector(createSurfaceWithModuleName:mode:initialProperties:)])
        {
            throw std::runtime_error("Fabric host does not expose surface creation");
        }
        id surface = [host createSurfaceWithModuleName:moduleName mode:0 initialProperties:properties];
        if (!surface)
        {
            throw std::runtime_error("Fabric host could not create the requested surface");
        }

        if (![surface respondsToSelector:@selector(start)] ||
            ![surface respondsToSelector:@selector(view)])
        {
            throw std::runtime_error("Fabric surface does not expose start and view");
        }

        fabricStart(surface);
        UIView *view = fabricView(surface);
        if (!view)
        {
            fabricStop(surface);
            throw std::runtime_error("Fabric surface did not create a view");
        }

        UIView *containerView = (UIView *) container;
        FabricContainer *surfaceContainer =
            [[FabricContainer alloc] initWithFrame:containerView.bounds];
        surfaceContainer.clipsToBounds = NO;
        surfaceContainer.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        surfaceContainer.surfaceView = view;
        view.frame = surfaceContainer.bounds;
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [surfaceContainer addSubview:view];
        [containerView addSubview:surfaceContainer];
        [surfaceContainer setNeedsLayout];
        [surfaceContainer layoutIfNeeded];
        surfaceHost->setSurface(surface, surfaceContainer, view);
    });

    return Object::createFromHostObject(runtime, std::move(surfaceHost));
}

static Value fabricUpdate(Runtime &runtime, const Value *args, size_t count)
{
    if (count < 2)
    {
        throw JSError(runtime, "fabric.update expects a surface and properties");
    }

    std::shared_ptr<FabricSurfaceHost> surfaceHost = fabricSurfaceHost(runtime, args[0]);
    NSDictionary *properties = fabricProperties(runtime, &args[1]);
    id surface = surfaceHost->surface();
    if (!surfaceHost->active() || !surface)
    {
        return Value::undefined();
    }

    executeMainSynchronously([surface, properties]() {
        if ([surface respondsToSelector:@selector(setProps:)])
        {
            fabricSetProps(surface, properties);
        }
    });
    return Value::undefined();
}

static Value fabricSetSize(Runtime &runtime, const Value *args, size_t count)
{
    if (count < 3)
    {
        throw JSError(runtime, "fabric.setSize expects a surface, minimum size, and maximum size");
    }

    std::shared_ptr<FabricSurfaceHost> surfaceHost = fabricSurfaceHost(runtime, args[0]);
    CGSize minimumSize = fabricSize(runtime, args[1]);
    CGSize maximumSize = fabricSize(runtime, args[2]);
    id surface = surfaceHost->surface();
    if (!surfaceHost->active() || !surface)
    {
        return Value::undefined();
    }

    executeMainSynchronously([surface, minimumSize, maximumSize]() {
        if ([surface respondsToSelector:@selector(setMinimumSize:maximumSize:)])
        {
            fabricSetMinimumSize(surface, minimumSize, maximumSize);
        }
    });
    return Value::undefined();
}

static Value fabricSetFrame(Runtime &runtime, const Value *args, size_t count)
{
    if (count < 2)
    {
        throw JSError(runtime, "fabric.setFrame expects a surface and frame");
    }

    std::shared_ptr<FabricSurfaceHost> surfaceHost = fabricSurfaceHost(runtime, args[0]);
    CGRect frame = fabricFrame(runtime, args[1]);
    UIView *view = surfaceHost->view();
    UIView *surfaceView = surfaceHost->surfaceView();
    if (!surfaceHost->active() || !view)
    {
        return Value::undefined();
    }

    executeMainSynchronously([view, surfaceView, frame]() {
        view.autoresizingMask = UIViewAutoresizingNone;
        if ([view respondsToSelector:@selector(setFabricFrame:)])
        {
            [(FabricContainer *) view setFabricFrame:frame];
        }
        else
        {
            view.frame = frame;
        }
        [view setNeedsLayout];
        [view layoutIfNeeded];
        if (surfaceView)
        {
            surfaceView.frame = view.bounds;
            surfaceView.autoresizingMask =
                UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        }
    });
    return Value::undefined();
}

static Value fabricMeasure(Runtime &runtime, const Value *args, size_t count)
{
    if (count == 0)
    {
        throw JSError(runtime, "fabric.measure expects a UIView");
    }

    id object = objcValue(runtime, args[0]);
    if (![object isKindOfClass:[UIView class]])
    {
        throw JSError(runtime, "fabric.measure expects a UIView");
    }

    CGRect frame = CGRectZero;
    executeMainSynchronously([object, &frame]() { frame = [(UIView *) object frame]; });

    Object result(runtime);
    result.setProperty(runtime, "x", frame.origin.x);
    result.setProperty(runtime, "y", frame.origin.y);
    result.setProperty(runtime, "width", frame.size.width);
    result.setProperty(runtime, "height", frame.size.height);
    return result;
}

static Value fabricUnmount(Runtime &runtime, const Value *args, size_t count)
{
    if (count == 0)
    {
        throw JSError(runtime, "fabric.unmount expects a surface");
    }

    std::shared_ptr<FabricSurfaceHost> surfaceHost = fabricSurfaceHost(runtime, args[0]);
    id surface = surfaceHost->surface();
    UIView *view = surfaceHost->view();
    if (!surfaceHost->active())
    {
        return Value::undefined();
    }

    executeMainSynchronously([surface, view]() {
        [view removeFromSuperview];
        if ([surface respondsToSelector:@selector(stop)])
        {
            fabricStop(surface);
        }
    });
    surfaceHost->clear();
    return Value::undefined();
}

static id valueToData(Runtime &runtime, const Value &value)
{
    if (!value.isObject())
    {
        return nil;
    }

    Object object = value.asObject(runtime);
    if (object.isArrayBuffer(runtime))
    {
        ArrayBuffer buffer = object.getArrayBuffer(runtime);
        return [NSData dataWithBytes:buffer.data(runtime) length:buffer.size(runtime)];
    }

    if (object.isTypedArray(runtime))
    {
        TypedArray array = object.getTypedArray(runtime);
        ArrayBuffer buffer = array.buffer(runtime);
        return [NSData dataWithBytes:buffer.data(runtime) + array.byteOffset(runtime)
                               length:array.byteLength(runtime)];
    }

    return nil;
}

static Value structResult(Runtime &runtime, NSString *name, NSValue *value)
{
    return Object::createFromHostObject(runtime, std::make_shared<StructHost>(name, value));
}

static Value structValue(Runtime &runtime, NSString *name, const Value &fields)
{
    if (!fields.isObject())
    {
        throw JSError(runtime, "Native struct fields must be an object");
    }

    Object object = fields.asObject(runtime);
    if ([name isEqualToString:@"NSRange"])
    {
        NSRange range = NSMakeRange((NSUInteger) object.getProperty(runtime, "location").asNumber(),
                                    (NSUInteger) object.getProperty(runtime, "length").asNumber());
        return structResult(runtime, name, [NSValue valueWithRange:range]);
    }
    if ([name isEqualToString:@"CGPoint"])
    {
        CGPoint point = CGPointMake(object.getProperty(runtime, "x").asNumber(),
                                    object.getProperty(runtime, "y").asNumber());
        return structResult(runtime, name, [NSValue valueWithCGPoint:point]);
    }
    if ([name isEqualToString:@"CGSize"])
    {
        CGSize size = CGSizeMake(object.getProperty(runtime, "width").asNumber(),
                                 object.getProperty(runtime, "height").asNumber());
        return structResult(runtime, name, [NSValue valueWithCGSize:size]);
    }
    if ([name isEqualToString:@"CGRect"])
    {
        Object origin = object.getPropertyAsObject(runtime, "origin");
        Object size = object.getPropertyAsObject(runtime, "size");
        CGRect rect = CGRectMake(origin.getProperty(runtime, "x").asNumber(),
                                 origin.getProperty(runtime, "y").asNumber(),
                                 size.getProperty(runtime, "width").asNumber(),
                                 size.getProperty(runtime, "height").asNumber());
        return structResult(runtime, name, [NSValue valueWithCGRect:rect]);
    }
    if ([name isEqualToString:@"UIEdgeInsets"])
    {
        UIEdgeInsets insets = UIEdgeInsetsMake(object.getProperty(runtime, "top").asNumber(),
                                               object.getProperty(runtime, "left").asNumber(),
                                               object.getProperty(runtime, "bottom").asNumber(),
                                               object.getProperty(runtime, "right").asNumber());
        return structResult(runtime, name, [NSValue valueWithUIEdgeInsets:insets]);
    }
    if ([name isEqualToString:@"CGAffineTransform"])
    {
        CGAffineTransform transform = CGAffineTransformMake(object.getProperty(runtime, "a").asNumber(),
                                                            object.getProperty(runtime, "b").asNumber(),
                                                            object.getProperty(runtime, "c").asNumber(),
                                                            object.getProperty(runtime, "d").asNumber(),
                                                            object.getProperty(runtime, "tx").asNumber(),
                                                            object.getProperty(runtime, "ty").asNumber());
        return structResult(runtime, name, [NSValue valueWithCGAffineTransform:transform]);
    }

    throw JSError(runtime, "Unsupported native struct");
}

static Value returnValue(Runtime &runtime, NSInvocation *invocation, NSMethodSignature *signature)
{
    const char *type = signature.methodReturnType;
    char code = normalizedType(type);
    NSUInteger length = signature.methodReturnLength;

    if (code == 'v' || length == 0)
    {
        return Value::undefined();
    }

    if (code == '@' || code == '#' || code == ':')
    {
        __unsafe_unretained id object = nil;
        [invocation getReturnValue:&object];
        return objcResult(runtime, object);
    }

    if (code == '^' || code == '*')
    {
        void *pointer = nullptr;
        [invocation getReturnValue:&pointer];
        return pointerResult(runtime, pointer);
    }

    if (code == 'B')
    {
        bool value = false;
        [invocation getReturnValue:&value];
        return Value(value);
    }

    if (code == 'c')
    {
        int8_t value = 0;
        [invocation getReturnValue:&value];
        return Value((double) value);
    }

    if (code == 'C')
    {
        uint8_t value = 0;
        [invocation getReturnValue:&value];
        return Value((double) value);
    }

    if (code == 's')
    {
        int16_t value = 0;
        [invocation getReturnValue:&value];
        return Value((double) value);
    }

    if (code == 'S')
    {
        uint16_t value = 0;
        [invocation getReturnValue:&value];
        return Value((double) value);
    }

    if (code == 'i')
    {
        int32_t value = 0;
        [invocation getReturnValue:&value];
        return Value((double) value);
    }

    if (code == 'I')
    {
        uint32_t value = 0;
        [invocation getReturnValue:&value];
        return Value((double) value);
    }

    if (code == 'l' || code == 'q')
    {
        int64_t value = 0;
        [invocation getReturnValue:&value];
        return Value(runtime, BigInt::fromInt64(runtime, (int64_t) value));
    }

    if (code == 'L' || code == 'Q')
    {
        uint64_t value = 0;
        [invocation getReturnValue:&value];
        return Value(runtime, BigInt::fromUint64(runtime, (uint64_t) value));
    }

    if (code == 'f')
    {
        float value = 0;
        [invocation getReturnValue:&value];
        return Value((double) value);
    }

    if (code == 'd')
    {
        double value = 0;
        [invocation getReturnValue:&value];
        return Value(value);
    }

    if (code == '{')
    {
        std::vector<uint8_t> bytes(length);
        [invocation getReturnValue:bytes.data()];
        NSString *typeName = [NSString stringWithUTF8String:type] ?: @"";
        NSValue *value = [NSValue value:bytes.data() withObjCType:type];
        return structResult(runtime, typeName, value);
    }

    throw JSError(runtime, "Unsupported native return type");
}

static void setInvocationArgument(Runtime &runtime, NSInvocation *invocation, NSMethodSignature *signature,
                                  id object, NSUInteger index, std::vector<id> &retained,
                                  std::vector<std::vector<uint8_t>> &storage)
{
    const char *type = [signature getArgumentTypeAtIndex:index];
    char code = normalizedType(type);

    if (code == '@')
    {
        id argument = object == [NSNull null] ? nil : object;
        if ([object isKindOfClass:[NSValue class]] &&
            strncmp([(NSValue *) object objCType], "^", 1) == 0)
        {
            argument = (__bridge id) [(NSValue *) object pointerValue];
        }
        retained.push_back(argument);
        id retainedArgument = retained.back();
        [invocation setArgument:&retainedArgument atIndex:index];
        return;
    }

    if (code == '#')
    {
        Class argument = object && object_isClass(object) ? object : Nil;
        [invocation setArgument:&argument atIndex:index];
        return;
    }

    if (code == ':')
    {
        SEL argument = NULL;
        if ([object isKindOfClass:[NSString class]])
        {
            argument = NSSelectorFromString((NSString *) object);
        }
        else if ([object isKindOfClass:[NSValue class]])
        {
            argument = (SEL) [(NSValue *) object pointerValue];
        }
        [invocation setArgument:&argument atIndex:index];
        return;
    }

    if (code == '^' || code == '*')
    {
        void *pointer = nullptr;
        if (code == '*' && [object isKindOfClass:[NSString class]])
        {
            retained.push_back(object);
            pointer = (void *) [(NSString *) object UTF8String];
        }
        else if ([object isKindOfClass:[NSValue class]])
        {
            pointer = [(NSValue *) object pointerValue];
        }
        [invocation setArgument:&pointer atIndex:index];
        return;
    }

    if (code == 'B')
    {
        bool argument = [object respondsToSelector:@selector(boolValue)] && [object boolValue];
        [invocation setArgument:&argument atIndex:index];
        return;
    }

    if (code == 'f')
    {
        float argument = [object respondsToSelector:@selector(floatValue)] ? [object floatValue] : 0;
        [invocation setArgument:&argument atIndex:index];
        return;
    }

    if (code == 'd')
    {
        double argument = [object respondsToSelector:@selector(doubleValue)] ? [object doubleValue] : 0;
        [invocation setArgument:&argument atIndex:index];
        return;
    }

    if (code == 'q')
    {
        long long argument = [object respondsToSelector:@selector(longLongValue)] ? [object longLongValue] : 0;
        [invocation setArgument:&argument atIndex:index];
        return;
    }

    if (code == 'Q')
    {
        unsigned long long argument =
            [object respondsToSelector:@selector(unsignedLongLongValue)] ? [object unsignedLongLongValue] : 0;
        [invocation setArgument:&argument atIndex:index];
        return;
    }

    if (code == 'c')
    {
        int8_t argument = [object respondsToSelector:@selector(charValue)] ? [object charValue] : 0;
        storage.emplace_back(sizeof(argument));
        memcpy(storage.back().data(), &argument, sizeof(argument));
        [invocation setArgument:storage.back().data() atIndex:index];
        return;
    }

    if (code == 'C')
    {
        uint8_t argument = [object respondsToSelector:@selector(unsignedCharValue)] ? [object unsignedCharValue] : 0;
        storage.emplace_back(sizeof(argument));
        memcpy(storage.back().data(), &argument, sizeof(argument));
        [invocation setArgument:storage.back().data() atIndex:index];
        return;
    }

    if (code == 's')
    {
        int16_t argument = [object respondsToSelector:@selector(shortValue)] ? [object shortValue] : 0;
        storage.emplace_back(sizeof(argument));
        memcpy(storage.back().data(), &argument, sizeof(argument));
        [invocation setArgument:storage.back().data() atIndex:index];
        return;
    }

    if (code == 'S')
    {
        uint16_t argument = [object respondsToSelector:@selector(unsignedShortValue)] ? [object unsignedShortValue] : 0;
        storage.emplace_back(sizeof(argument));
        memcpy(storage.back().data(), &argument, sizeof(argument));
        [invocation setArgument:storage.back().data() atIndex:index];
        return;
    }

    if (code == 'i')
    {
        int32_t argument = [object respondsToSelector:@selector(intValue)] ? [object intValue] : 0;
        storage.emplace_back(sizeof(argument));
        memcpy(storage.back().data(), &argument, sizeof(argument));
        [invocation setArgument:storage.back().data() atIndex:index];
        return;
    }

    if (code == 'I')
    {
        uint32_t argument = [object respondsToSelector:@selector(unsignedIntValue)] ? [object unsignedIntValue] : 0;
        storage.emplace_back(sizeof(argument));
        memcpy(storage.back().data(), &argument, sizeof(argument));
        [invocation setArgument:storage.back().data() atIndex:index];
        return;
    }

    if (code == 'l' || code == 'q')
    {
        int64_t argument = [object respondsToSelector:@selector(longLongValue)] ? [object longLongValue] : 0;
        storage.emplace_back(sizeof(argument));
        memcpy(storage.back().data(), &argument, sizeof(argument));
        [invocation setArgument:storage.back().data() atIndex:index];
        return;
    }

    if (code == 'L' || code == 'Q')
    {
        uint64_t argument = [object respondsToSelector:@selector(unsignedLongLongValue)]
                                ? [object unsignedLongLongValue]
                                : 0;
        storage.emplace_back(sizeof(argument));
        memcpy(storage.back().data(), &argument, sizeof(argument));
        [invocation setArgument:storage.back().data() atIndex:index];
        return;
    }

    if (code == '{')
    {
        if (![object isKindOfClass:[NSValue class]])
        {
            throw JSError(runtime, "Native struct argument expected");
        }

        NSValue *structValue = (NSValue *) object;
        NSUInteger size = 0;
        NSUInteger alignment = 0;
        NSGetSizeAndAlignment(type, &size, &alignment);
        storage.emplace_back(size);
        [structValue getValue:storage.back().data() size:size];
        [invocation setArgument:storage.back().data() atIndex:index];
        return;
    }

    throw JSError(runtime, "Unsupported native argument type");
}

static Value invokeObject(Runtime &runtime, id target, SEL selector, NSArray *arguments)
{
    if (!target || !selector)
    {
        throw JSError(runtime, "Invalid native Objective-C target or selector");
    }

    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature)
    {
        throw JSError(runtime, "Objective-C selector is not available");
    }

    NSUInteger expected = signature.numberOfArguments >= 2 ? signature.numberOfArguments - 2 : 0;
    if (expected != arguments.count)
    {
        throw JSError(runtime, "Objective-C argument count does not match the method signature");
    }

    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = target;
    invocation.selector = selector;

    std::vector<id> retained;
    std::vector<std::vector<uint8_t>> storage;
    retained.reserve(arguments.count);
    storage.reserve(arguments.count);

    for (NSUInteger index = 0; index < arguments.count; index++)
    {
        setInvocationArgument(runtime, invocation, signature, arguments[index], index + 2, retained, storage);
    }

    [invocation invoke];
    return returnValue(runtime, invocation, signature);
}

static std::string nativeFFITypeName(const char *encoding)
{
    char code = normalizedType(encoding);
    switch (code)
    {
        case 'v':
            return "void";
        case '@':
            return "object";
        case '#':
            return "class";
        case ':':
            return "selector";
        case '^':
        case '*':
            return "pointer";
        case 'B':
            return "bool";
        case 'c':
            return "i8";
        case 'C':
            return "u8";
        case 's':
            return "i16";
        case 'S':
            return "u16";
        case 'i':
            return "i32";
        case 'I':
            return "u32";
        case 'l':
            return "i64";
        case 'L':
            return "u64";
        case 'q':
            return "i64";
        case 'Q':
            return "u64";
        case 'f':
            return "float";
        case 'd':
            return "double";
        case '{':
        {
            std::string value(encoding ?: "");
            if (value.find("_NSRange") != std::string::npos)
            {
                return "struct:NSRange";
            }
            if (value.find("CGPoint") != std::string::npos)
            {
                return "struct:CGPoint";
            }
            if (value.find("CGSize") != std::string::npos)
            {
                return "struct:CGSize";
            }
            if (value.find("CGRect") != std::string::npos)
            {
                return "struct:CGRect";
            }
            if (value.find("UIEdgeInsets") != std::string::npos)
            {
                return "struct:UIEdgeInsets";
            }
            if (value.find("CGAffineTransform") != std::string::npos)
            {
                return "struct:CGAffineTransform";
            }
            break;
        }
        default:
            break;
    }
    return std::string();
}

static void setSuperFFIArgument(Runtime &runtime, const char *encoding, id object,
                                 FFICallArgument &argument, std::vector<id> &retained)
{
    char code = normalizedType(encoding);
    id value = object == [NSNull null] ? @0 : object;
    if (code == '@' || code == '#')
    {
        id retainedValue = object == [NSNull null] ? nil : object;
        retained.push_back(retainedValue);
        argument.pointer = (__bridge void *) retainedValue;
        return;
    }
    if (code == ':')
    {
        if ([value isKindOfClass:[NSString class]])
        {
            argument.pointer = (void *) sel_registerName([(NSString *) value UTF8String]);
        }
        else if ([value isKindOfClass:[NSValue class]])
        {
            argument.pointer = [(NSValue *) value pointerValue];
        }
        return;
    }
    if (code == '^' || code == '*')
    {
        if (code == '*' && [value isKindOfClass:[NSString class]])
        {
            argument.string = [(NSString *) value UTF8String] ?: "";
            argument.pointer = (void *) argument.string.c_str();
        }
        else if ([value isKindOfClass:[NSValue class]])
        {
            argument.pointer = [(NSValue *) value pointerValue];
        }
        return;
    }
    if (code == 'B')
    {
        bool scalar = [value boolValue];
        argument.bytes.resize(sizeof(scalar));
        memcpy(argument.bytes.data(), &scalar, sizeof(scalar));
        return;
    }
    if (code == 'c' || code == 'C')
    {
        uint8_t scalar = code == 'c' ? (uint8_t) [value charValue] : [value unsignedCharValue];
        argument.bytes.resize(sizeof(scalar));
        memcpy(argument.bytes.data(), &scalar, sizeof(scalar));
        return;
    }
    if (code == 's' || code == 'S')
    {
        uint16_t scalar = code == 's' ? (uint16_t) [value shortValue] : [value unsignedShortValue];
        argument.bytes.resize(sizeof(scalar));
        memcpy(argument.bytes.data(), &scalar, sizeof(scalar));
        return;
    }
    if (code == 'i' || code == 'I')
    {
        uint32_t scalar = code == 'i' ? (uint32_t) [value intValue] : [value unsignedIntValue];
        argument.bytes.resize(sizeof(scalar));
        memcpy(argument.bytes.data(), &scalar, sizeof(scalar));
        return;
    }
    if (code == 'l' || code == 'L' || code == 'q' || code == 'Q')
    {
        uint64_t scalar = code == 'l' || code == 'q' ? (uint64_t) [value longLongValue]
                                                       : [value unsignedLongLongValue];
        argument.bytes.resize(sizeof(scalar));
        memcpy(argument.bytes.data(), &scalar, sizeof(scalar));
        return;
    }
    if (code == 'f')
    {
        float scalar = [value floatValue];
        argument.bytes.resize(sizeof(scalar));
        memcpy(argument.bytes.data(), &scalar, sizeof(scalar));
        return;
    }
    if (code == 'd')
    {
        double scalar = [value doubleValue];
        argument.bytes.resize(sizeof(scalar));
        memcpy(argument.bytes.data(), &scalar, sizeof(scalar));
        return;
    }
    if (code == '{')
    {
        NSUInteger size = 0;
        NSUInteger alignment = 0;
        NSGetSizeAndAlignment(encoding, &size, &alignment);
        if (![value isKindOfClass:[NSValue class]])
        {
            throw JSError(runtime, "Native super struct argument expected");
        }
        argument.bytes.resize(size);
        [(NSValue *) value getValue:argument.bytes.data() size:size];
        return;
    }
    throw JSError(runtime, "Unsupported native super argument type");
}

static Value invokeSuperObject(Runtime &runtime, id target, Class currentClass, SEL selector,
                               NSArray *arguments)
{
    if (!target || !currentClass || !selector)
    {
        throw JSError(runtime, "Invalid native Objective-C super target");
    }

    Class superclass = class_getSuperclass(currentClass);
    Method method = superclass ? class_getInstanceMethod(superclass, selector) : NULL;
    if (!method)
    {
        throw JSError(runtime, "Objective-C super selector is not available");
    }

    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    NSUInteger expected = signature.numberOfArguments >= 2 ? signature.numberOfArguments - 2 : 0;
    if (expected != arguments.count)
    {
        throw JSError(runtime, "Objective-C super argument count does not match the method signature");
    }

    std::vector<FFITypeSpec> types;
    std::vector<FFICallArgument> values(arguments.count + 2);
    std::vector<void *> argumentValues(arguments.count + 2);
    std::vector<id> retained;
    types.reserve(arguments.count);
    retained.reserve(arguments.count);

    struct objc_super superInfo = {target, currentClass};
    values[0].pointer = &superInfo;
    values[1].pointer = selector;
    argumentValues[0] = &values[0].pointer;
    argumentValues[1] = &values[1].pointer;

    for (NSUInteger index = 0; index < arguments.count; index++)
    {
        const char *encoding = [signature getArgumentTypeAtIndex:index + 2];
        std::string name = nativeFFITypeName(encoding);
        if (name.empty())
        {
            throw JSError(runtime, "Unsupported native super argument type encoding");
        }
        types.push_back(ffiType(runtime, name));
        setSuperFFIArgument(runtime, encoding, arguments[index], values[index + 2], retained);
        if (name == "object" || name == "class" || name == "selector" || name == "pointer")
        {
            argumentValues[index + 2] = &values[index + 2].pointer;
        }
        else
        {
            argumentValues[index + 2] = values[index + 2].bytes.data();
        }
    }

    std::string resultName = nativeFFITypeName(signature.methodReturnType);
    if (resultName.empty())
    {
        throw JSError(runtime, "Unsupported native super return type encoding");
    }
    FFITypeSpec result = ffiType(runtime, resultName);
    std::vector<FFITypeSpec> cifArguments;
    cifArguments.reserve(types.size() + 2);
    cifArguments.push_back({"pointer", &ffi_type_pointer});
    cifArguments.push_back({"selector", &ffi_type_pointer});
    cifArguments.insert(cifArguments.end(), types.begin(), types.end());
    ffi_cif cif = prepareFFICif(runtime, result, cifArguments);

    std::vector<uint8_t> output(std::max<size_t>(result.type->size, sizeof(void *)));
    ffi_call(&cif, reinterpret_cast<void (*)(void)>(objc_msgSendSuper),
             resultName == "void" ? nullptr : output.data(), argumentValues.data());
    return ffiResult(runtime, result, output);
}

static Value invokeWithThreadPolicy(Runtime &runtime, id target, SEL selector, NSArray *arguments,
                                    const Value *options)
{
    std::string policy = "current";
    if (options && options->isObject())
    {
        Value thread = options->asObject(runtime).getProperty(runtime, "thread");
        if (thread.isString())
        {
            policy = [JSI toNSString:thread runtime:runtime].UTF8String;
        }
    }
    if (policy == "current" || ([NSThread isMainThread] && policy == "main"))
    {
        return invokeObject(runtime, target, selector, arguments);
    }
    if (policy != "main")
    {
        throw JSError(runtime, "Unsupported native thread policy");
    }

    __block Value result = Value::undefined();
    __block std::exception_ptr failure;
    dispatch_sync(dispatch_get_main_queue(), ^{
        try
        {
            result = invokeObject(runtime, target, selector, arguments);
        }
        catch (...)
        {
            failure = std::current_exception();
        }
    });
    if (failure)
    {
        std::rethrow_exception(failure);
    }
    return std::move(result);
}

static Value invokeSuperWithThreadPolicy(Runtime &runtime, id target, Class currentClass, SEL selector,
                                         NSArray *arguments, const Value *options)
{
    std::string policy = "current";
    if (options && options->isObject())
    {
        Value thread = options->asObject(runtime).getProperty(runtime, "thread");
        if (thread.isString())
        {
            policy = [JSI toNSString:thread runtime:runtime].UTF8String;
        }
    }
    if (policy == "current" || ([NSThread isMainThread] && policy == "main"))
    {
        return invokeSuperObject(runtime, target, currentClass, selector, arguments);
    }
    if (policy != "main")
    {
        throw JSError(runtime, "Unsupported native thread policy");
    }

    __block Value result = Value::undefined();
    __block std::exception_ptr failure;
    dispatch_sync(dispatch_get_main_queue(), ^{
        try
        {
            result = invokeSuperObject(runtime, target, currentClass, selector, arguments);
        }
        catch (...)
        {
            failure = std::current_exception();
        }
    });
    if (failure)
    {
        std::rethrow_exception(failure);
    }
    return std::move(result);
}

static NSArray *argumentArray(Runtime &runtime, const Value *args, size_t count, size_t start)
{
    NSMutableArray *arguments = [NSMutableArray arrayWithCapacity:count - start];
    for (size_t index = start; index < count; index++)
    {
        const Value &value = args[index];
        if (value.isObject() && value.asObject(runtime).isHostObject<ObjCHandleHost>(runtime))
        {
            [arguments addObject:objcValue(runtime, value) ?: [NSNull null]];
        }
        else
        {
            [arguments addObject:valueToObjC(runtime, value) ?: [NSNull null]];
        }
    }
    return arguments;
}

static Class classFromValue(Runtime &runtime, const Value &value)
{
    id object = objcValue(runtime, value);
    if (object && object_isClass(object))
    {
        return object;
    }

    if (value.isString())
    {
        NSString *name = [JSI toNSString:value runtime:runtime];
        return NSClassFromString(name);
    }

    return Nil;
}

static void removeHook(const std::shared_ptr<HookState> &state)
{
    if (!state || !state->active.exchange(false))
    {
        return;
    }
    clearHookReturnCache(state);

    std::shared_ptr<HookDispatcher> dispatcher = state->dispatcher.lock();
    if (!dispatcher)
    {
        return;
    }

    bool retired = false;
    {
        std::lock_guard<std::mutex> lock(gHookMutex);
        auto iterator = std::find(dispatcher->hooks.begin(), dispatcher->hooks.end(), state);
        if (iterator != dispatcher->hooks.end())
        {
            dispatcher->hooks.erase(iterator);
        }

        if (dispatcher->hooks.empty() && !dispatcher->retired.exchange(true))
        {
            Method method = class_getInstanceMethod(dispatcher->cls, dispatcher->selector);
            if (method && method_getImplementation(method) == (IMP) dispatcher->code)
            {
                method_setImplementation(method, dispatcher->original);
            }
            gDispatchers.erase(hookKey(dispatcher->cls, dispatcher->selector));
            retired = true;
        }
    }

    if (retired) releaseHookClosure(dispatcher);
}

Value HookTokenHost::get(Runtime &runtime, const PropNameID &name)
{
    std::string property = name.utf8(runtime);
    if (property == "remove")
    {
        std::shared_ptr<HookState> state = state_;
        return Function::createFromHostFunction(
            runtime, PropNameID::forUtf8(runtime, "remove"), 0,
            [state](Runtime &, const Value &, const Value *, size_t) -> Value {
                removeHook(state);
                return Value::undefined();
            });
    }
    if (property == "active")
    {
        return Value(state_ && state_->active.load());
    }
    if (property == "setReturnValue")
    {
        std::shared_ptr<HookState> state = state_;
        return Function::createFromHostFunction(
            runtime, PropNameID::forUtf8(runtime, "setReturnValue"), 3,
            [state](Runtime &rt, const Value &, const Value *args, size_t count) -> Value {
                setHookReturnCache(rt, state, args, count);
                return Value::undefined();
            });
    }
    if (property == "removeReturnValue")
    {
        std::shared_ptr<HookState> state = state_;
        return Function::createFromHostFunction(
            runtime, PropNameID::forUtf8(runtime, "removeReturnValue"), 2,
            [state](Runtime &rt, const Value &, const Value *args, size_t count) -> Value {
                removeHookReturnCache(rt, state, args, count);
                return Value::undefined();
            });
    }
    if (property == "clearReturnValues")
    {
        std::shared_ptr<HookState> state = state_;
        return Function::createFromHostFunction(
            runtime, PropNameID::forUtf8(runtime, "clearReturnValues"), 0,
            [state](Runtime &, const Value &, const Value *, size_t) -> Value {
                clearHookReturnCache(state);
                return Value::undefined();
            });
    }
    return Value::undefined();
}

static const char *structEncoding(const std::string &name)
{
    if (name == "NSRange")
    {
        return "{_NSRange=QQ}";
    }
    if (name == "CGPoint")
    {
        return "{CGPoint=dd}";
    }
    if (name == "CGSize")
    {
        return "{CGSize=dd}";
    }
    if (name == "CGRect")
    {
        return "{CGRect={CGPoint=dd}{CGSize=dd}}";
    }
    if (name == "UIEdgeInsets")
    {
        return "{UIEdgeInsets=dddd}";
    }
    if (name == "CGAffineTransform")
    {
        return "{CGAffineTransform=dddddd}";
    }
    return nullptr;
}

Value StructHost::get(Runtime &runtime, const PropNameID &name)
{
    std::string property = name.utf8(runtime);
    if (property == "name")
    {
        return String::createFromUtf8(runtime, name_.UTF8String ?: "");
    }
    if (property == "value")
    {
        return structFields(runtime, name_, value_);
    }
    return Value::undefined();
}

static Value structFields(Runtime &runtime, NSString *name, NSValue *value)
{
    if (!value)
    {
        return Value::undefined();
    }

    NSString *canonicalName = name;
    if ([name containsString:@"_NSRange"])
    {
        canonicalName = @"NSRange";
    }
    else if ([name containsString:@"CGAffineTransform"])
    {
        canonicalName = @"CGAffineTransform";
    }
    else if ([name containsString:@"UIEdgeInsets"])
    {
        canonicalName = @"UIEdgeInsets";
    }
    else if ([name containsString:@"CGRect"])
    {
        canonicalName = @"CGRect";
    }
    else if ([name containsString:@"CGPoint"])
    {
        canonicalName = @"CGPoint";
    }
    else if ([name containsString:@"CGSize"])
    {
        canonicalName = @"CGSize";
    }

    Object result(runtime);
    if ([canonicalName isEqualToString:@"NSRange"])
    {
        NSRange range = NSMakeRange(0, 0);
        [value getValue:&range];
        result.setProperty(runtime, "location", (double) range.location);
        result.setProperty(runtime, "length", (double) range.length);
        return result;
    }
    if ([canonicalName isEqualToString:@"CGPoint"])
    {
        CGPoint point = CGPointZero;
        [value getValue:&point];
        result.setProperty(runtime, "x", point.x);
        result.setProperty(runtime, "y", point.y);
        return result;
    }
    if ([canonicalName isEqualToString:@"CGSize"])
    {
        CGSize size = CGSizeZero;
        [value getValue:&size];
        result.setProperty(runtime, "width", size.width);
        result.setProperty(runtime, "height", size.height);
        return result;
    }
    if ([canonicalName isEqualToString:@"CGRect"])
    {
        CGRect rect = CGRectZero;
        [value getValue:&rect];
        Object origin(runtime);
        origin.setProperty(runtime, "x", rect.origin.x);
        origin.setProperty(runtime, "y", rect.origin.y);
        Object size(runtime);
        size.setProperty(runtime, "width", rect.size.width);
        size.setProperty(runtime, "height", rect.size.height);
        result.setProperty(runtime, "origin", origin);
        result.setProperty(runtime, "size", size);
        return result;
    }
    if ([canonicalName isEqualToString:@"UIEdgeInsets"])
    {
        UIEdgeInsets insets = UIEdgeInsetsZero;
        [value getValue:&insets];
        result.setProperty(runtime, "top", insets.top);
        result.setProperty(runtime, "left", insets.left);
        result.setProperty(runtime, "bottom", insets.bottom);
        result.setProperty(runtime, "right", insets.right);
        return result;
    }
    if ([canonicalName isEqualToString:@"CGAffineTransform"])
    {
        CGAffineTransform transform = CGAffineTransformIdentity;
        [value getValue:&transform];
        result.setProperty(runtime, "a", transform.a);
        result.setProperty(runtime, "b", transform.b);
        result.setProperty(runtime, "c", transform.c);
        result.setProperty(runtime, "d", transform.d);
        result.setProperty(runtime, "tx", transform.tx);
        result.setProperty(runtime, "ty", transform.ty);
        return result;
    }
    return Value::undefined();
}

static ffi_type *ffiStructTypeLocked(const std::string &name)
{
    auto existing = gFFITypes.find(name);
    if (existing != gFFITypes.end())
    {
        return &existing->second->type;
    }

    auto definition = std::make_shared<FFITypeDefinition>();
    if (name == "NSRange")
    {
        definition->elements = {&ffi_type_uint64, &ffi_type_uint64, nullptr};
    }
    else if (name == "CGPoint" || name == "CGSize")
    {
        definition->elements = {&ffi_type_double, &ffi_type_double, nullptr};
    }
    else if (name == "CGRect")
    {
        ffi_type *point = ffiStructTypeLocked("CGPoint");
        ffi_type *size = ffiStructTypeLocked("CGSize");
        definition->elements = {point, size, nullptr};
    }
    else if (name == "UIEdgeInsets")
    {
        definition->elements = {
            &ffi_type_double,
            &ffi_type_double,
            &ffi_type_double,
            &ffi_type_double,
            nullptr,
        };
    }
    else if (name == "CGAffineTransform")
    {
        definition->elements = {
            &ffi_type_double,
            &ffi_type_double,
            &ffi_type_double,
            &ffi_type_double,
            &ffi_type_double,
            &ffi_type_double,
            nullptr,
        };
    }
    else
    {
        return nullptr;
    }

    definition->type.type = FFI_TYPE_STRUCT;
    definition->type.elements = definition->elements.data();
    gFFITypes[name] = definition;
    return &definition->type;
}

static ffi_type *ffiStructType(const std::string &name)
{
    std::lock_guard<std::mutex> lock(gFFIMutex);
    return ffiStructTypeLocked(name);
}

static FFITypeSpec ffiType(Runtime &runtime, const std::string &name)
{
    if (name == "void")
    {
        return {name, &ffi_type_void};
    }
    if (name == "bool" || name == "i8")
    {
        return {name, &ffi_type_sint8};
    }
    if (name == "u8")
    {
        return {name, &ffi_type_uint8};
    }
    if (name == "i16")
    {
        return {name, &ffi_type_sint16};
    }
    if (name == "u16")
    {
        return {name, &ffi_type_uint16};
    }
    if (name == "i32")
    {
        return {name, &ffi_type_sint32};
    }
    if (name == "u32")
    {
        return {name, &ffi_type_uint32};
    }
    if (name == "i64")
    {
        return {name, &ffi_type_sint64};
    }
    if (name == "u64")
    {
        return {name, &ffi_type_uint64};
    }
    if (name == "float")
    {
        return {name, &ffi_type_float};
    }
    if (name == "double")
    {
        return {name, &ffi_type_double};
    }
    if (name == "cstring" || name == "pointer" || name == "object" || name == "class" ||
        name == "selector")
    {
        return {name, &ffi_type_pointer};
    }
    if (name.rfind("struct:", 0) == 0)
    {
        std::string structName = name.substr(7);
        if (ffi_type *type = ffiStructType(structName))
        {
            return {name, type};
        }
    }

    throw JSError(runtime, "Unsupported native FFI type");
}

static std::string ffiCifKey(const FFITypeSpec &result, const std::vector<FFITypeSpec> &arguments)
{
    std::ostringstream key;
    key << result.name;
    for (const FFITypeSpec &argument : arguments)
    {
        key << '\0' << argument.name;
    }
    return key.str();
}

static ffi_cif prepareFFICif(Runtime &runtime, const FFITypeSpec &result,
                             const std::vector<FFITypeSpec> &arguments)
{
    std::string key = ffiCifKey(result, arguments);
    {
        std::lock_guard<std::mutex> lock(gFFICifMutex);
        auto existing = gFFICifs.find(key);
        if (existing != gFFICifs.end())
        {
            return existing->second->cif;
        }
    }

    auto cached = std::make_shared<CachedFFICif>();
    cached->arguments.reserve(arguments.size());
    for (const FFITypeSpec &argument : arguments)
    {
        cached->arguments.push_back(argument.type);
    }

    if (ffi_prep_cif(&cached->cif, FFI_DEFAULT_ABI, (unsigned) cached->arguments.size(), result.type,
                     cached->arguments.data()) != FFI_OK)
    {
        throw JSError(runtime, "Native FFI signature could not be prepared");
    }

    std::lock_guard<std::mutex> lock(gFFICifMutex);
    auto existing = gFFICifs.find(key);
    if (existing != gFFICifs.end())
    {
        return existing->second->cif;
    }
    gFFICifs.emplace(std::move(key), cached);
    return cached->cif;
}

static std::string ffiTypeName(Runtime &runtime, const Value &value)
{
    if (value.isString())
    {
        return [JSI toNSString:value runtime:runtime].UTF8String;
    }

    if (value.isObject())
    {
        Object object = value.asObject(runtime);
        Value structName = object.getProperty(runtime, "struct");
        if (structName.isString())
        {
            return "struct:" + std::string([JSI toNSString:structName runtime:runtime].UTF8String);
        }
        Value typeName = object.getProperty(runtime, "type");
        if (typeName.isString())
        {
            return [JSI toNSString:typeName runtime:runtime].UTF8String;
        }
    }

    throw JSError(runtime, "Native FFI type must be a string or type object");
}

static FFISignature parseFFISignature(Runtime &runtime, const Value &value)
{
    if (!value.isObject())
    {
        throw JSError(runtime, "ffi.call expects a signature object");
    }

    Object signature = value.asObject(runtime);
    Value resultValue = signature.getProperty(runtime, "returnType");
    if (resultValue.isUndefined())
    {
        resultValue = signature.getProperty(runtime, "returns");
    }
    if (resultValue.isUndefined())
    {
        throw JSError(runtime, "Native FFI signature is missing returnType");
    }

    Value argumentsValue = signature.getProperty(runtime, "args");
    if (!argumentsValue.isObject() || !argumentsValue.asObject(runtime).isArray(runtime))
    {
        throw JSError(runtime, "Native FFI signature is missing args");
    }

    FFISignature result{ffiType(runtime, ffiTypeName(runtime, resultValue)), {}};
    Array arguments = argumentsValue.asObject(runtime).asArray(runtime);
    result.arguments.reserve(arguments.size(runtime));
    for (size_t index = 0; index < arguments.size(runtime); index++)
    {
        result.arguments.push_back(ffiType(runtime, ffiTypeName(runtime, arguments.getValueAtIndex(runtime, index))));
    }
    return result;
}

static void setFFIScalar(Runtime &runtime, const Value &value, const std::string &name,
                         FFICallArgument &argument)
{
    id object = valueToObjC(runtime, value);
    if (name == "bool" || name == "i8" || name == "u8")
    {
        argument.bytes.resize(1);
        argument.bytes[0] = name == "bool" ? [object boolValue] : [object unsignedCharValue];
        return;
    }
    if (name == "i16" || name == "u16")
    {
        argument.bytes.resize(2);
        uint16_t number = name == "i16" ? (uint16_t) [object shortValue] : [object unsignedShortValue];
        memcpy(argument.bytes.data(), &number, sizeof(number));
        return;
    }
    if (name == "i32" || name == "u32")
    {
        argument.bytes.resize(4);
        uint32_t number = name == "i32" ? (uint32_t) [object intValue] : [object unsignedIntValue];
        memcpy(argument.bytes.data(), &number, sizeof(number));
        return;
    }
    if (name == "i64" || name == "u64")
    {
        argument.bytes.resize(8);
        uint64_t number = name == "i64" ? (uint64_t) [object longLongValue]
                                         : [object unsignedLongLongValue];
        memcpy(argument.bytes.data(), &number, sizeof(number));
        return;
    }
    if (name == "float")
    {
        argument.bytes.resize(sizeof(float));
        float number = [object floatValue];
        memcpy(argument.bytes.data(), &number, sizeof(number));
        return;
    }
    if (name == "double")
    {
        argument.bytes.resize(sizeof(double));
        double number = [object doubleValue];
        memcpy(argument.bytes.data(), &number, sizeof(number));
        return;
    }
}

static void setFFIArgument(Runtime &runtime, const Value &value, const FFITypeSpec &spec,
                           FFICallArgument &argument)
{
    if (spec.name == "cstring")
    {
        NSString *string = [JSI toNSString:value runtime:runtime];
        argument.string = string.UTF8String ?: "";
        argument.pointer = (void *) argument.string.c_str();
        return;
    }

    if (spec.name == "selector")
    {
        if (value.isString())
        {
            NSString *name = [JSI toNSString:value runtime:runtime];
            argument.pointer = (void *) NSSelectorFromString(name);
        }
        else if (value.isObject())
        {
            Object object = value.asObject(runtime);
            if (object.isHostObject<PointerHost>(runtime))
            {
                argument.pointer = object.getHostObject<PointerHost>(runtime)->value();
            }
        }
        return;
    }

    if (spec.name == "pointer" || spec.name == "object" || spec.name == "class")
    {
        argument.pointer = (__bridge void *) objcValue(runtime, value);
        if (!argument.pointer && value.isObject())
        {
            Object object = value.asObject(runtime);
            if (object.isHostObject<PointerHost>(runtime))
            {
                argument.pointer = object.getHostObject<PointerHost>(runtime)->value();
            }
        }
        return;
    }

    if (spec.name.rfind("struct:", 0) == 0)
    {
        id object = valueToObjC(runtime, value);
        if (![object isKindOfClass:[NSValue class]])
        {
            throw JSError(runtime, "Native FFI struct argument expected");
        }
        NSUInteger size = spec.type->size;
        argument.bytes.resize(size);
        [(NSValue *) object getValue:argument.bytes.data() size:size];
        return;
    }

    setFFIScalar(runtime, value, spec.name, argument);
}

struct HookInvocation {
    std::shared_ptr<HookDispatcher> dispatcher;
    std::vector<std::vector<uint8_t>> arguments;
    std::vector<std::shared_ptr<ObjCHandleHost>> retainedObjects;
    std::vector<std::string> retainedStrings;
    std::vector<uint8_t> originalResult;
    void **nativeArguments = nullptr;
    void *returnValue = nullptr;
    std::thread::id hookThread;
    std::mutex lifecycleMutex;
    std::atomic_bool active{true};
    std::atomic_bool originalCalled{false};
};

struct RuntimeCallState {
    explicit RuntimeCallState(std::function<void(Runtime &)> callback)
        : callback(std::move(callback)), semaphore(dispatch_semaphore_create(0))
    {
    }

    std::function<void(Runtime &)> callback;
    std::exception_ptr failure;
    dispatch_semaphore_t semaphore;
    std::atomic_bool cancelled{false};
};

static std::shared_ptr<HookInvocation> hookInvocation(const std::shared_ptr<HookDispatcher> &dispatcher,
                                                      void **arguments, void *returnValue)
{
    auto invocation = std::make_shared<HookInvocation>();
    invocation->dispatcher = dispatcher;
    invocation->nativeArguments = arguments;
    invocation->returnValue = returnValue;
    invocation->hookThread = std::this_thread::get_id();
    invocation->arguments.reserve(dispatcher->signature->arguments.size());
    invocation->retainedObjects.reserve(dispatcher->signature->arguments.size());
    invocation->retainedStrings.reserve(dispatcher->signature->arguments.size());
    for (const FFITypeSpec &spec : dispatcher->signature->arguments)
    {
        size_t size = std::max<size_t>(spec.type->size, sizeof(void *));
        invocation->arguments.emplace_back(size);
        if (spec.type->size)
        {
            memcpy(invocation->arguments.back().data(), arguments[invocation->arguments.size() - 1],
                   spec.type->size);
        }
        if (spec.name == "object" || spec.name == "class")
        {
            void *rawObject = nullptr;
            memcpy(&rawObject, invocation->arguments.back().data(), sizeof(rawObject));
            id object = (__bridge id) rawObject;
            if (object)
            {
                invocation->retainedObjects.emplace_back(std::make_shared<ObjCHandleHost>(object));
            }
        }
        else if (spec.name == "cstring")
        {
            const char *string = nullptr;
            memcpy(&string, invocation->arguments.back().data(), sizeof(string));
            if (string)
            {
                invocation->retainedStrings.emplace_back(string);
                string = invocation->retainedStrings.back().c_str();
                memcpy(invocation->arguments.back().data(), &string, sizeof(string));
            }
        }
    }
    return invocation;
}

static void copyHookResult(const std::shared_ptr<HookInvocation> &invocation, void *returnValue)
{
    if (invocation->dispatcher->signature->result.name == "void" || !returnValue)
    {
        invocation->originalResult.clear();
        return;
    }

    size_t size = std::max<size_t>(invocation->dispatcher->signature->result.type->size, sizeof(void *));
    invocation->originalResult.resize(size);
    memcpy(invocation->originalResult.data(), returnValue,
           invocation->dispatcher->signature->result.type->size);
}

static std::shared_ptr<std::vector<uint8_t>> hookReturnBuffer(
    const std::shared_ptr<HookInvocation> &invocation)
{
    size_t size = std::max<size_t>(invocation->dispatcher->signature->result.type->size,
                                   sizeof(void *));
    return std::make_shared<std::vector<uint8_t>>(size);
}

static void copyHookReturnBuffer(const std::shared_ptr<HookInvocation> &invocation,
                                 const std::shared_ptr<std::vector<uint8_t>> &buffer,
                                 void *returnValue)
{
    if (invocation->dispatcher->signature->result.name == "void" || !returnValue)
    {
        return;
    }

    memcpy(returnValue, buffer->data(), invocation->dispatcher->signature->result.type->size);
}

static Object hookContext(Runtime &runtime, const std::shared_ptr<HookInvocation> &invocation,
                          id object, SEL selector, bool allowOriginal)
{
    Object context(runtime);
    context.setProperty(runtime, "self",
                        Object::createFromHostObject(runtime, std::make_shared<ObjCHandleHost>(object)));
    context.setProperty(runtime, "selector",
                        String::createFromUtf8(runtime, sel_getName(selector)));

    size_t explicitCount = invocation->dispatcher->signature->arguments.size() - 2;
    Array values(runtime, explicitCount);
    for (size_t index = 0; index < explicitCount; index++)
    {
        values.setValueAtIndex(
            runtime, index,
            ffiResult(runtime, invocation->dispatcher->signature->arguments[index + 2],
                      invocation->arguments[index + 2]));
    }
    context.setProperty(runtime, "args", std::move(values));

    auto original = invocation;
    context.setProperty(
        runtime, "replaceObjectArgument",
        Function::createFromHostFunction(
            runtime, PropNameID::forUtf8(runtime, "replaceObjectArgument"), 2,
            [original, allowOriginal](Runtime &rt, const Value &, const Value *args,
                                     size_t count) -> Value {
                std::lock_guard<std::mutex> lock(original->lifecycleMutex);
                if (!original->active.load())
                {
                    throw JSError(rt, "Native hook arguments are unavailable after the hook returns");
                }
                if (!allowOriginal)
                {
                    throw JSError(rt, "Native hook arguments can only be replaced synchronously");
                }
                if (std::this_thread::get_id() != original->hookThread)
                {
                    throw JSError(rt, "Native hook arguments cannot cross runtime threads");
                }
                if (count < 2 || !args[0].isNumber())
                {
                    throw JSError(rt, "Native hook replaceObjectArgument expects an index and object");
                }

                double requestedIndex = args[0].getNumber();
                size_t explicitCount = original->dispatcher->signature->arguments.size() - 2;
                if (!(requestedIndex >= 0 && requestedIndex < explicitCount))
                {
                    throw JSError(rt, "Native hook argument index is out of range");
                }
                size_t explicitIndex = static_cast<size_t>(requestedIndex);
                if (static_cast<double>(explicitIndex) != requestedIndex)
                {
                    throw JSError(rt, "Native hook argument index must be an integer");
                }

                size_t argumentIndex = explicitIndex + 2;
                const FFITypeSpec &spec = original->dispatcher->signature->arguments[argumentIndex];
                if (spec.name != "object" && spec.name != "class")
                {
                    throw JSError(rt, "Native hook argument is not an Objective-C object");
                }

                id object = args[1].isNull() ? nil : objcValue(rt, args[1]);
                void *rawObject = (__bridge void *) object;
                if (object)
                {
                    original->retainedObjects.emplace_back(std::make_shared<ObjCHandleHost>(object));
                }
                memcpy(original->arguments[argumentIndex].data(), &rawObject, sizeof(rawObject));
                memcpy(original->nativeArguments[argumentIndex], &rawObject, sizeof(rawObject));
                return Value::undefined();
            }));
    context.setProperty(
        runtime, "original",
        Function::createFromHostFunction(
            runtime, PropNameID::forUtf8(runtime, "original"), 0,
            [original, allowOriginal](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                std::lock_guard<std::mutex> lock(original->lifecycleMutex);
                if (!original->active.load())
                {
                    throw JSError(rt, "Native hook original() is unavailable after the hook returns");
                }
                if (!allowOriginal)
                {
                    throw JSError(rt, "Native hook original() is only available synchronously");
                }
                if (!original->originalCalled.load())
                {
                    if (std::this_thread::get_id() != original->hookThread)
                    {
                        throw JSError(rt, "Native hook original() cannot cross runtime threads");
                    }

                    invokeHookOriginal(original->dispatcher, original->nativeArguments,
                                       original->returnValue);
                    copyHookResult(original, original->returnValue);
                    original->originalCalled.store(true);
                }
                return ffiResult(rt, original->dispatcher->signature->result, original->originalResult);
            }));
    return context;
}

static bool executeRuntimeSynchronously(std::function<void(Runtime &)> callback)
{
    id instance = gRuntimeExecutorInstance;
    if (!instance)
    {
        return false;
    }

    if (gNativePluginRuntime && std::this_thread::get_id() == gNativePluginRuntimeThread)
    {
        callback(*gNativePluginRuntime);
        return true;
    }

    auto state = std::make_shared<RuntimeCallState>(std::move(callback));
    [instance callFunctionOnBufferedRuntimeExecutor:[state](Runtime &runtime) {
        @autoreleasepool
        {
            if (!state->cancelled.load())
            {
                try
                {
                    state->callback(runtime);
                }
                catch (...)
                {
                    state->failure = std::current_exception();
                }
            }
            dispatch_semaphore_signal(state->semaphore);
        }
    }];

    if (dispatch_semaphore_wait(state->semaphore,
                                dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC)) != 0)
    {
        state->cancelled.store(true);
        return false;
    }
    if (state->failure)
    {
        std::rethrow_exception(state->failure);
    }
    return true;
}

static void executeRuntimeAsynchronously(std::function<void(Runtime &)> callback)
{
    id instance = gRuntimeExecutorInstance;
    if (!instance)
    {
        return;
    }

    [instance callFunctionOnBufferedRuntimeExecutor:[callback = std::move(callback)](Runtime &runtime) {
        @autoreleasepool
        {
            try
            {
                callback(runtime);
            }
            catch (const std::exception &exception)
            {
                [Logger error:LOG_CATEGORY_PLUGINS
                        format:@"Native plugin hook failed: %s", exception.what()];
            }
        }
    }];
}

static void invokeHookOriginal(const std::shared_ptr<HookDispatcher> &dispatcher, void **arguments,
                               void *returnValue)
{
    ffi_call(&dispatcher->signature->cif, reinterpret_cast<void (*)(void)>(dispatcher->original),
             dispatcher->signature->result.name == "void" ? nullptr : returnValue, arguments);
}

static bool setHookReturn(Runtime &runtime, const FFITypeSpec &spec, const Value &value,
                          void *returnValue)
{
    if (spec.name == "void")
    {
        return true;
    }
    if (!returnValue)
    {
        return false;
    }

    FFICallArgument argument{};
    setFFIArgument(runtime, value, spec, argument);
    if (spec.name == "cstring" || spec.name == "pointer" || spec.name == "object" ||
        spec.name == "class" || spec.name == "selector")
    {
        memcpy(returnValue, &argument.pointer, sizeof(argument.pointer));
        return true;
    }
    if (argument.bytes.size() < spec.type->size)
    {
        return false;
    }
    memcpy(returnValue, argument.bytes.data(), spec.type->size);
    return true;
}

static id hookCacheComponent(const FFITypeSpec &spec, const FFICallArgument &argument)
{
    if (spec.name == "object" || spec.name == "class")
    {
        id object = (__bridge id) argument.pointer;
        return object ?: [NSNull null];
    }
    if (spec.name == "selector")
    {
        SEL selector = (SEL) argument.pointer;
        return selector ? NSStringFromSelector(selector) : [NSNull null];
    }
    if (spec.name == "pointer")
    {
        return [NSValue valueWithPointer:argument.pointer];
    }
    if (spec.name == "cstring")
    {
        const char *string = (const char *) argument.pointer;
        return string ? ([NSString stringWithUTF8String:string] ?: [NSNull null]) : [NSNull null];
    }
    if (spec.name == "bool")
    {
        return @(*(const bool *) argument.bytes.data());
    }
    if (spec.name == "i8")
    {
        return @(*(const int8_t *) argument.bytes.data());
    }
    if (spec.name == "u8")
    {
        return @(*(const uint8_t *) argument.bytes.data());
    }
    if (spec.name == "i16")
    {
        return @(*(const int16_t *) argument.bytes.data());
    }
    if (spec.name == "u16")
    {
        return @(*(const uint16_t *) argument.bytes.data());
    }
    if (spec.name == "i32")
    {
        return @(*(const int32_t *) argument.bytes.data());
    }
    if (spec.name == "u32")
    {
        return @(*(const uint32_t *) argument.bytes.data());
    }
    if (spec.name == "i64")
    {
        return @(*(const int64_t *) argument.bytes.data());
    }
    if (spec.name == "u64")
    {
        return @(*(const uint64_t *) argument.bytes.data());
    }
    if (spec.name == "float")
    {
        return @(*(const float *) argument.bytes.data());
    }
    if (spec.name == "double")
    {
        return @(*(const double *) argument.bytes.data());
    }
    if (spec.name.rfind("struct:", 0) == 0)
    {
        const char *encoding = structEncoding(spec.name.substr(7));
        if (!encoding || argument.bytes.size() < spec.type->size)
        {
            return nil;
        }
        return [NSValue value:argument.bytes.data() withObjCType:encoding];
    }
    return nil;
}

static NSArray *hookReturnCacheKey(Runtime &runtime, const std::shared_ptr<HookState> &state,
                                   const Value *args, size_t count)
{
    if (!state || !state->cacheOnly || count < 2 || !args[1].isObject() ||
        !args[1].asObject(runtime).isArray(runtime))
    {
        throw JSError(runtime, "Native hook return caching is unavailable");
    }

    std::shared_ptr<HookDispatcher> dispatcher = state->dispatcher.lock();
    if (!dispatcher)
    {
        throw JSError(runtime, "Native hook has been removed");
    }

    id target = objcValue(runtime, args[0]);
    Array values = args[1].asObject(runtime).asArray(runtime);
    size_t expected = dispatcher->signature->arguments.size() - 2;
    if (!target || values.size(runtime) != expected)
    {
        throw JSError(runtime, "Native hook return cache arguments do not match the method");
    }

    NSMutableArray *components = [NSMutableArray arrayWithCapacity:expected + 2];
    [components addObject:target];
    [components addObject:NSStringFromSelector(dispatcher->selector)];
    for (size_t index = 0; index < expected; index++)
    {
        FFICallArgument argument{};
        setFFIArgument(runtime, values.getValueAtIndex(runtime, index),
                       dispatcher->signature->arguments[index + 2], argument);
        id component = hookCacheComponent(dispatcher->signature->arguments[index + 2], argument);
        if (!component)
        {
            throw JSError(runtime, "Native hook return cache argument type is unsupported");
        }
        [components addObject:component];
    }
    return [components copy];
}

static NSArray *hookReturnCacheKey(const std::shared_ptr<HookDispatcher> &dispatcher,
                                   void **arguments)
{
    if (!dispatcher || !arguments)
    {
        return nil;
    }

    NSMutableArray *components =
        [NSMutableArray arrayWithCapacity:dispatcher->signature->arguments.size()];
    for (size_t index = 0; index < dispatcher->signature->arguments.size(); index++)
    {
        const FFITypeSpec &spec = dispatcher->signature->arguments[index];
        FFICallArgument argument{};
        if (spec.name == "object" || spec.name == "class" || spec.name == "selector" ||
            spec.name == "pointer" || spec.name == "cstring")
        {
            memcpy(&argument.pointer, arguments[index], sizeof(argument.pointer));
        }
        else
        {
            argument.bytes.resize(spec.type->size);
            memcpy(argument.bytes.data(), arguments[index], spec.type->size);
        }
        id component = hookCacheComponent(spec, argument);
        if (!component)
        {
            return nil;
        }
        [components addObject:component];
    }
    return [components copy];
}

static void setHookReturnCache(Runtime &runtime, const std::shared_ptr<HookState> &state,
                               const Value *args, size_t count)
{
    if (!state || !state->cacheOnly || count < 3)
    {
        throw JSError(runtime, "Native hook does not support cached return values");
    }

    std::shared_ptr<HookDispatcher> dispatcher = state->dispatcher.lock();
    if (!dispatcher)
    {
        throw JSError(runtime, "Native hook has been removed");
    }

    const FFITypeSpec &result = dispatcher->signature->result;
    std::vector<uint8_t> bytes(std::max<size_t>(result.type->size, sizeof(void *)));
    if (!setHookReturn(runtime, result, args[2], bytes.data()))
    {
        throw JSError(runtime, "Native hook return value has an unsupported type");
    }

    NSArray *key = hookReturnCacheKey(runtime, state, args, count);
    NSData *value = [NSData dataWithBytes:bytes.data() length:result.type->size];
    std::lock_guard<std::mutex> lock(state->returnCacheMutex);
    state->returnCache[key] = value;
}

static void removeHookReturnCache(Runtime &runtime, const std::shared_ptr<HookState> &state,
                                  const Value *args, size_t count)
{
    NSArray *key = hookReturnCacheKey(runtime, state, args, count);
    std::lock_guard<std::mutex> lock(state->returnCacheMutex);
    [state->returnCache removeObjectForKey:key];
}

static void clearHookReturnCache(const std::shared_ptr<HookState> &state)
{
    if (!state)
    {
        return;
    }
    std::lock_guard<std::mutex> lock(state->returnCacheMutex);
    [state->returnCache removeAllObjects];
}

static Value ffiResult(Runtime &runtime, const FFITypeSpec &spec, const std::vector<uint8_t> &bytes)
{
    if (spec.name == "void")
    {
        return Value::undefined();
    }
    if (spec.name == "bool")
    {
        return Value(bytes[0] != 0);
    }
    if (spec.name == "i8")
    {
        return Value((double) *(const int8_t *) bytes.data());
    }
    if (spec.name == "u8")
    {
        return Value((double) bytes[0]);
    }
    if (spec.name == "i16")
    {
        return Value((double) *(const int16_t *) bytes.data());
    }
    if (spec.name == "u16")
    {
        return Value((double) *(const uint16_t *) bytes.data());
    }
    if (spec.name == "i32")
    {
        return Value((double) *(const int32_t *) bytes.data());
    }
    if (spec.name == "u32")
    {
        return Value((double) *(const uint32_t *) bytes.data());
    }
    if (spec.name == "i64")
    {
        return Value(runtime, BigInt::fromInt64(runtime, *(const int64_t *) bytes.data()));
    }
    if (spec.name == "u64")
    {
        return Value(runtime, BigInt::fromUint64(runtime, *(const uint64_t *) bytes.data()));
    }
    if (spec.name == "float")
    {
        return Value((double) *(const float *) bytes.data());
    }
    if (spec.name == "double")
    {
        return Value(*(const double *) bytes.data());
    }
    if (spec.name == "cstring")
    {
        const char *string = *(const char *const *) bytes.data();
        return string ? String::createFromUtf8(runtime, string) : Value::null();
    }
    if (spec.name == "object" || spec.name == "class")
    {
        __unsafe_unretained id object = nil;
        memcpy(&object, bytes.data(), sizeof(object));
        return objcResult(runtime, object);
    }
    if (spec.name == "selector")
    {
        SEL selector = NULL;
        memcpy(&selector, bytes.data(), sizeof(selector));
        return selector ? String::createFromUtf8(runtime, sel_getName(selector)) : Value::null();
    }
    if (spec.name == "pointer")
    {
        return pointerResult(runtime, *(void *const *) bytes.data());
    }
    if (spec.name.rfind("struct:", 0) == 0)
    {
        std::string name = spec.name.substr(7);
        const char *encoding = structEncoding(name);
        if (!encoding)
        {
            throw JSError(runtime, "Native FFI struct result is not registered");
        }
        NSValue *value = [NSValue value:bytes.data() withObjCType:encoding];
        return structResult(runtime, [NSString stringWithUTF8String:name.c_str()] ?: @"", value);
    }
    throw JSError(runtime, "Unsupported native FFI result type");
}

static Value ffiCall(Runtime &runtime, void *pointer, const FFISignature &signature,
                     const Value *args)
{
    std::vector<FFICallArgument> arguments(signature.arguments.size());
    std::vector<void *> argumentValues(signature.arguments.size());
    for (size_t index = 0; index < signature.arguments.size(); index++)
    {
        setFFIArgument(runtime, args[index], signature.arguments[index], arguments[index]);
        if (signature.arguments[index].name == "pointer" ||
            signature.arguments[index].name == "object" || signature.arguments[index].name == "class" ||
            signature.arguments[index].name == "selector" || signature.arguments[index].name == "cstring")
        {
            argumentValues[index] = &arguments[index].pointer;
        }
        else
        {
            argumentValues[index] = arguments[index].bytes.data();
        }
    }

    ffi_cif cif = prepareFFICif(runtime, signature.result, signature.arguments);

    size_t resultSize = signature.result.type->size;
    std::vector<uint8_t> result(std::max<size_t>(resultSize, sizeof(void *)));
    ffi_call(&cif, reinterpret_cast<void (*)(void)>(pointer),
             signature.result.name == "void" ? nullptr : result.data(), argumentValues.data());
    return ffiResult(runtime, signature.result, result);
}

static Value ffiCallValue(Runtime &runtime, const Value *args, size_t count)
{
    if (count < 2 || !args[0].isObject())
    {
        throw JSError(runtime, "ffi.call expects a pointer, signature, and arguments");
    }

    Object pointer = args[0].asObject(runtime);
    if (!pointer.isHostObject<PointerHost>(runtime))
    {
        throw JSError(runtime, "ffi.call expects a pointer handle");
    }

    void *address = pointer.getHostObject<PointerHost>(runtime)->value();
    if (!address)
    {
        throw JSError(runtime, "ffi.call cannot invoke a null pointer");
    }

    FFISignature signature = parseFFISignature(runtime, args[1]);
    if (signature.arguments.size() != count - 2)
    {
        throw JSError(runtime, "Native FFI argument count does not match the signature");
    }
    return ffiCall(runtime, address, signature, args + 2);
}

static void releaseHookClosure(const std::shared_ptr<HookDispatcher> &dispatcher)
{
    if (!dispatcher || !dispatcher->retired || dispatcher->activeCalls.load() != 0 ||
        dispatcher->closureReleased.exchange(true))
    {
        return;
    }

    ffi_closure *closure = dispatcher->closure;
    dispatcher->closure = nullptr;
    if (closure)
    {
        ffi_closure_free(closure);
    }
}

static std::shared_ptr<HookDispatcher> findHookDispatcher(id object, SEL selector)
{
    std::lock_guard<std::mutex> lock(gHookMutex);
    auto iterator = gDispatchers.find(hookKey(object_getClass(object), selector));
    if (iterator == gDispatchers.end())
    {
        Class cls = object_getClass(object);
        while (cls && iterator == gDispatchers.end())
        {
            iterator = gDispatchers.find(hookKey(cls, selector));
            cls = class_getSuperclass(cls);
        }
    }
    if (iterator == gDispatchers.end())
    {
        return nullptr;
    }

    iterator->second->activeCalls.fetch_add(1);
    return iterator->second;
}

struct HookCallGuard {
    explicit HookCallGuard(std::shared_ptr<HookDispatcher> dispatcher)
        : dispatcher(std::move(dispatcher))
    {
    }

    ~HookCallGuard()
    {
        if (dispatcher->activeCalls.fetch_sub(1) == 1)
        {
            releaseHookClosure(dispatcher);
        }
    }

    std::shared_ptr<HookDispatcher> dispatcher;
};

static void logHookFailure(const std::exception &exception)
{
    [Logger error:LOG_CATEGORY_PLUGINS format:@"Native plugin hook failed: %s", exception.what()];
}

static void dispatchFFIHookBody(ffi_cif *, void *returnValue, void **arguments, void *userData)
{
    __unsafe_unretained id object = nil;
    memcpy(&object, arguments[0], sizeof(object));
    SEL selector = *reinterpret_cast<SEL *>(arguments[1]);
    auto dispatcher = findHookDispatcher(object, selector);
    if (!dispatcher)
    {
        return;
    }

    HookCallGuard guard(dispatcher);
    if (userData && dispatcher.get() != userData)
    {
        return;
    }

    std::vector<std::shared_ptr<HookState>> hooks;
    {
        std::lock_guard<std::mutex> lock(gHookMutex);
        for (const std::shared_ptr<HookState> &state : dispatcher->hooks)
        {
            if (state->active && (!state->instanceTarget || state->instanceTarget == object))
            {
                hooks.push_back(state);
            }
        }
    }
    if (hooks.empty())
    {
        invokeHookOriginal(dispatcher, arguments, returnValue);
        return;
    }

    bool cacheOnly = true;
    for (const std::shared_ptr<HookState> &state : hooks)
    {
        if (state->active && !state->cacheOnly)
        {
            cacheOnly = false;
            break;
        }
    }
    if (cacheOnly)
    {
        bool cachedReturn = false;
        std::vector<std::shared_ptr<HookState>> onceHooks;
        for (const std::shared_ptr<HookState> &state : hooks)
        {
            if (!state->active)
            {
                continue;
            }

            NSArray *key = hookReturnCacheKey(dispatcher, arguments);
            NSData *cached = nil;
            if (key)
            {
                std::lock_guard<std::mutex> lock(state->returnCacheMutex);
                cached = state->returnCache[key];
            }
            if (cached && returnValue &&
                cached.length == dispatcher->signature->result.type->size)
            {
                memcpy(returnValue, cached.bytes, cached.length);
                cachedReturn = true;
            }
            if (state->once)
            {
                onceHooks.push_back(state);
            }
        }

        if (!cachedReturn)
        {
            invokeHookOriginal(dispatcher, arguments, returnValue);
        }
        for (const std::shared_ptr<HookState> &state : onceHooks)
        {
            removeHook(state);
        }
        return;
    }

    auto invocation = hookInvocation(dispatcher, arguments, returnValue);

    bool replacementApplied = false;
    bool originalCalled = false;
    std::vector<std::shared_ptr<HookState>> onceHooks;

    for (const std::shared_ptr<HookState> &state : hooks)
    {
        if (!state->active)
        {
            continue;
        }

        if (state->cacheOnly)
        {
            NSArray *key = hookReturnCacheKey(dispatcher, arguments);
            NSData *cached = nil;
            if (key)
            {
                std::lock_guard<std::mutex> lock(state->returnCacheMutex);
                cached = state->returnCache[key];
            }
            if (cached && returnValue &&
                cached.length == dispatcher->signature->result.type->size)
            {
                memcpy(returnValue, cached.bytes, cached.length);
                replacementApplied = true;
            }
            if (state->once)
            {
                onceHooks.push_back(state);
            }
            continue;
        }

        if (state->before)
        {
            try
            {
                executeRuntimeSynchronously([invocation, object, selector, state](Runtime &runtime) {
                    Object context = hookContext(runtime, invocation, object, selector, true);
                    state->before->call(runtime, context);
                });
            }
            catch (const std::exception &exception)
            {
                logHookFailure(exception);
            }
        }

        if (invocation->originalCalled.load() && !originalCalled)
        {
            originalCalled = true;
        }

        if (state->replace)
        {
            try
            {
                std::shared_ptr<std::vector<uint8_t>> replacementResult = hookReturnBuffer(invocation);
                bool completed = executeRuntimeSynchronously(
                    [invocation, object, selector, state, replacementResult](Runtime &runtime) {
                        Object context = hookContext(runtime, invocation, object, selector, true);
                        Value result = state->replace->call(runtime, context);
                        if (!setHookReturn(runtime, invocation->dispatcher->signature->result, result,
                                           replacementResult->data()))
                        {
                            throw JSError(runtime, "Native hook replacement returned an unsupported value");
                        }
                    });
                if (completed)
                {
                    replacementApplied = true;
                    copyHookReturnBuffer(invocation, replacementResult, returnValue);
                    copyHookResult(invocation, returnValue);
                }
            }
            catch (const std::exception &exception)
            {
                logHookFailure(exception);
            }
        }

        if (state->once)
        {
            onceHooks.push_back(state);
        }
    }

    if (!originalCalled && !replacementApplied)
    {
        invokeHookOriginal(dispatcher, arguments, returnValue);
        copyHookResult(invocation, returnValue);
    }

    for (const std::shared_ptr<HookState> &state : hooks)
    {
        if (!state->active || !state->after)
        {
            continue;
        }

        std::shared_ptr<Function> callback = state->after;
        __strong id retainedObject = object;
        executeRuntimeAsynchronously([invocation, retainedObject, selector, callback, state](Runtime &runtime) {
            if (!state->active.load())
            {
                return;
            }
            Object context = hookContext(runtime, invocation, retainedObject, selector, false);
            callback->call(runtime, context);
        });
    }

    {
        std::lock_guard<std::mutex> lock(invocation->lifecycleMutex);
        invocation->active.store(false);
    }

    for (const std::shared_ptr<HookState> &state : onceHooks)
    {
        removeHook(state);
    }
}

static void dispatchFFIHook(ffi_cif *cif, void *returnValue, void **arguments, void *userData)
{
    @autoreleasepool
    {
        dispatchFFIHookBody(cif, returnValue, arguments, userData);
    }
}

static CGSize dispatchCGSizeHook(id object, SEL selector, CGSize size)
{
    @autoreleasepool
    {
        void *arguments[] = {&object, &selector, &size};
        CGSize result = CGSizeZero;
        dispatchFFIHookBody(nullptr, &result, arguments, nullptr);
        return result;
    }
}

static CGSize dispatchCGSizePriorityHook(id object, SEL selector, CGSize size, float horizontal,
                                        float vertical)
{
    @autoreleasepool
    {
        void *arguments[] = {&object, &selector, &size, &horizontal, &vertical};
        CGSize result = CGSizeZero;
        dispatchFFIHookBody(nullptr, &result, arguments, nullptr);
        return result;
    }
}

static CGSize dispatchCGSizeDoublePriorityHook(id object, SEL selector, CGSize size, double horizontal,
                                               double vertical)
{
    @autoreleasepool
    {
        void *arguments[] = {&object, &selector, &size, &horizontal, &vertical};
        CGSize result = CGSizeZero;
        dispatchFFIHookBody(nullptr, &result, arguments, nullptr);
        return result;
    }
}

static CGRect dispatchCGRectObjectHook(id object, SEL selector, id indexPath)
{
    @autoreleasepool
    {
        void *arguments[] = {&object, &selector, &indexPath};
        CGRect result = CGRectZero;
        dispatchFFIHookBody(nullptr, &result, arguments, nullptr);
        return result;
    }
}

static double dispatchDoubleObjectObjectHook(id object, SEL selector, id tableView, id indexPath)
{
    @autoreleasepool
    {
        void *arguments[] = {&object, &selector, &tableView, &indexPath};
        double result = 0;
        dispatchFFIHookBody(nullptr, &result, arguments, nullptr);
        return result;
    }
}

static void dispatchVoidObjectObjectObjectHook(id object, SEL selector, id tableView, id cell,
                                               id indexPath)
{
    @autoreleasepool
    {
        void *arguments[] = {&object, &selector, &tableView, &cell, &indexPath};
        dispatchFFIHookBody(nullptr, nullptr, arguments, nullptr);
    }
}

static void dispatchVoidObjectHook(id object, SEL selector, id value)
{
    @autoreleasepool
    {
        void *arguments[] = {&object, &selector, &value};
        dispatchFFIHookBody(nullptr, nullptr, arguments, nullptr);
    }
}

static void dispatchVoidObjectObjectHook(id object, SEL selector, id first, id second)
{
    @autoreleasepool
    {
        void *arguments[] = {&object, &selector, &first, &second};
        dispatchFFIHookBody(nullptr, nullptr, arguments, nullptr);
    }
}

static void *fallbackHookCode(const HookSignature &signature)
{
    if (signature.result.name == "void" && signature.arguments.size() == 3 &&
        signature.arguments[2].name == "object")
    {
        return reinterpret_cast<void *>(dispatchVoidObjectHook);
    }

    if (signature.result.name == "void" && signature.arguments.size() == 4 &&
        signature.arguments[2].name == "object" && signature.arguments[3].name == "object")
    {
        return reinterpret_cast<void *>(dispatchVoidObjectObjectHook);
    }

    if (signature.result.name == "void" && signature.arguments.size() == 5 &&
        signature.arguments[2].name == "object" && signature.arguments[3].name == "object" &&
        signature.arguments[4].name == "object")
    {
        return reinterpret_cast<void *>(dispatchVoidObjectObjectObjectHook);
    }

    if (signature.result.name == "struct:CGRect" && signature.arguments.size() == 3 &&
        signature.arguments[2].name == "object")
    {
        return reinterpret_cast<void *>(dispatchCGRectObjectHook);
    }

    if (signature.result.name == "double" && signature.arguments.size() == 4 &&
        signature.arguments[2].name == "object" && signature.arguments[3].name == "object")
    {
        return reinterpret_cast<void *>(dispatchDoubleObjectObjectHook);
    }

    if (signature.result.name != "struct:CGSize")
    {
        return nullptr;
    }

    if (signature.arguments.size() == 3 && signature.arguments[2].name == "struct:CGSize")
    {
        return reinterpret_cast<void *>(dispatchCGSizeHook);
    }

    if (signature.arguments.size() == 5 && signature.arguments[2].name == "struct:CGSize" &&
        signature.arguments[3].name == "float" && signature.arguments[4].name == "float")
    {
        return reinterpret_cast<void *>(dispatchCGSizePriorityHook);
    }

    if (signature.arguments.size() == 5 && signature.arguments[2].name == "struct:CGSize" &&
        signature.arguments[3].name == "double" && signature.arguments[4].name == "double")
    {
        return reinterpret_cast<void *>(dispatchCGSizeDoublePriorityHook);
    }

    return nullptr;
}

static void dispatchVoidHook(id object, SEL selector)
{
    @autoreleasepool
    {
        auto dispatcher = findHookDispatcher(object, selector);
        if (!dispatcher)
        {
            return;
        }

        HookCallGuard guard(dispatcher);
        void *arguments[] = {&object, &selector};
        auto invocation = hookInvocation(dispatcher, arguments, nullptr);

        std::vector<std::shared_ptr<HookState>> hooks;
        {
            std::lock_guard<std::mutex> lock(gHookMutex);
            for (const std::shared_ptr<HookState> &state : dispatcher->hooks)
            {
                if (state->active && (!state->instanceTarget || state->instanceTarget == object))
                {
                    hooks.push_back(state);
                }
            }
        }
        if (hooks.empty())
        {
            invokeHookOriginal(dispatcher, arguments, nullptr);
            return;
        }

        bool replacementApplied = false;
        bool originalCalled = false;
        std::vector<std::shared_ptr<HookState>> onceHooks;

        for (const std::shared_ptr<HookState> &state : hooks)
        {
            if (!state->active)
            {
                continue;
            }

            if (state->before)
            {
                try
                {
                    executeRuntimeSynchronously([invocation, object, selector, state](Runtime &runtime) {
                        Object context = hookContext(runtime, invocation, object, selector, true);
                        state->before->call(runtime, context);
                    });
                }
                catch (const std::exception &exception)
                {
                    logHookFailure(exception);
                }
            }

            if (invocation->originalCalled.load() && !originalCalled)
            {
                originalCalled = true;
            }

            if (state->replace)
            {
                try
                {
                    std::shared_ptr<std::vector<uint8_t>> replacementResult = hookReturnBuffer(invocation);
                    bool completed = executeRuntimeSynchronously(
                        [invocation, object, selector, state, replacementResult](Runtime &runtime) {
                            Object context = hookContext(runtime, invocation, object, selector, true);
                            Value result = state->replace->call(runtime, context);
                            if (!setHookReturn(runtime, invocation->dispatcher->signature->result, result,
                                               replacementResult->data()))
                            {
                                throw JSError(runtime, "Native hook replacement returned an unsupported value");
                            }
                        });
                    if (completed)
                    {
                        replacementApplied = true;
                        copyHookResult(invocation, nullptr);
                    }
                }
                catch (const std::exception &exception)
                {
                    logHookFailure(exception);
                }
            }

            if (state->once)
            {
                onceHooks.push_back(state);
            }
        }

        if (!originalCalled && !replacementApplied)
        {
            invokeHookOriginal(dispatcher, arguments, nullptr);
            copyHookResult(invocation, nullptr);
        }

        for (const std::shared_ptr<HookState> &state : hooks)
        {
            if (!state->active || !state->after)
            {
                continue;
            }

            std::shared_ptr<Function> callback = state->after;
            __strong id retainedObject = object;
            executeRuntimeAsynchronously([invocation, retainedObject, selector, callback, state](Runtime &runtime) {
                if (!state->active.load())
                {
                    return;
                }
                Object context = hookContext(runtime, invocation, retainedObject, selector, false);
                callback->call(runtime, context);
            });
        }

        {
            std::lock_guard<std::mutex> lock(invocation->lifecycleMutex);
            invocation->active.store(false);
        }

        for (const std::shared_ptr<HookState> &state : onceHooks)
        {
            removeHook(state);
        }
    }
}

static Value makeHook(Runtime &runtime, const Value *args, size_t count)
{
    if (count < 3 || !args[0].isString() || !args[1].isString() || !args[2].isObject())
    {
        throw JSError(runtime, "objc.hook expects a class, selector, and handlers");
    }

    NSString *className = [JSI toNSString:args[0] runtime:runtime];
    NSString *selectorName = [JSI toNSString:args[1] runtime:runtime];
    Class cls = NSClassFromString(className);
    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod(cls, selector);
    if (!cls || !method)
    {
        throw JSError(runtime, "Objective-C hook target is unavailable");
    }

    NSMethodSignature *methodSignature =
        [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    auto signature = std::make_shared<HookSignature>();
    std::string resultName = nativeFFITypeName(methodSignature.methodReturnType);
    if (resultName.empty())
    {
        throw JSError(runtime, "Unsupported native hook return type encoding");
    }
    signature->result = ffiType(runtime, resultName);
    for (NSUInteger index = 0; index < methodSignature.numberOfArguments; index++)
    {
        std::string name = nativeFFITypeName([methodSignature getArgumentTypeAtIndex:index]);
        if (name.empty())
        {
            throw JSError(runtime, "Unsupported native hook argument type encoding");
        }
        signature->arguments.push_back(ffiType(runtime, name));
    }
    signature->cif = prepareFFICif(runtime, signature->result, signature->arguments);

    Object handlers = args[2].asObject(runtime);
    auto functionFor = [&](const char *name) -> std::shared_ptr<Function> {
        Value value = handlers.getProperty(runtime, name);
        if (value.isUndefined() || value.isNull())
        {
            return nullptr;
        }
        if (!value.isObject() || !value.asObject(runtime).isFunction(runtime))
        {
            throw JSError(runtime, "Native hook handlers must be functions");
        }
        return std::make_shared<Function>(value.asObject(runtime).getFunction(runtime));
    };

    std::shared_ptr<Function> before = functionFor("before");
    std::shared_ptr<Function> after = functionFor("after");
    std::shared_ptr<Function> replace = functionFor("replace");
    bool once = false;
    bool cacheOnly = false;
    id instanceTarget = nil;
    if (count > 3 && args[3].isObject())
    {
        Object options = args[3].asObject(runtime);
        Value onceValue = options.getProperty(runtime, "once");
        once = onceValue.isBool() && onceValue.getBool();
        Value cacheOnlyValue = options.getProperty(runtime, "cacheOnly");
        cacheOnly = cacheOnlyValue.isBool() && cacheOnlyValue.getBool();
        Value instanceValue = options.getProperty(runtime, "instance");
        if (!instanceValue.isUndefined() && !instanceValue.isNull())
        {
            instanceTarget = objcValue(runtime, instanceValue);
            if (!instanceTarget)
            {
                throw JSError(runtime, "Native hook instance target must be an Objective-C handle");
            }
        }
    }
    if (!before && !after && !replace && !cacheOnly)
    {
        throw JSError(runtime, "objc.hook requires at least one handler");
    }
    if (cacheOnly)
    {
        const std::string &result = signature->result.name;
        bool supportedResult = result == "bool" || result == "i8" || result == "u8" ||
                               result == "i16" || result == "u16" || result == "i32" ||
                               result == "u32" || result == "i64" || result == "u64" ||
                               result == "float" || result == "double" ||
                               result.rfind("struct:", 0) == 0;
        if (before || after || replace || !supportedResult)
        {
            throw JSError(runtime, "Native cache-only hooks require a scalar or struct return type");
        }
    }

    std::shared_ptr<HookDispatcher> dispatcher;
    std::string key = hookKey(cls, selector);
    {
        std::lock_guard<std::mutex> lock(gHookMutex);
        auto iterator = gDispatchers.find(key);
        if (iterator == gDispatchers.end())
        {
            dispatcher = std::make_shared<HookDispatcher>();
            dispatcher->cls = cls;
            dispatcher->selector = selector;
            dispatcher->original = method_getImplementation(method);
            dispatcher->signature = signature;
            auto prepareClosure = [&]() {
                dispatcher->closure = (ffi_closure *) ffi_closure_alloc(sizeof(ffi_closure),
                                                                          &dispatcher->code);
                bool closureReady =
                    dispatcher->closure && isExecutableAddress(dispatcher->code) &&
                    ffi_prep_closure_loc(dispatcher->closure, &dispatcher->signature->cif,
                                         dispatchFFIHook, dispatcher.get(), dispatcher->code) == FFI_OK;
                if (!closureReady)
                {
                    if (dispatcher->closure) ffi_closure_free(dispatcher->closure);
                    dispatcher->closure = nullptr;
                    dispatcher->code = nullptr;
                    throw JSError(runtime, "Native hook closure is unavailable on this device");
                }
            };
            if (signature->result.name == "void")
            {
                if (signature->arguments.size() == 2)
                {
                    dispatcher->code = (void *) dispatchVoidHook;
                }
                else
                {
                    dispatcher->code = fallbackHookCode(*dispatcher->signature);
                    if (!dispatcher->code)
                    {
                        prepareClosure();
                    }
                }
            }
            else
            {
                dispatcher->code = fallbackHookCode(*dispatcher->signature);
                if (!dispatcher->code)
                {
                    prepareClosure();
                }
            }
            method_setImplementation(method, (IMP) dispatcher->code);
            gDispatchers[key] = dispatcher;
        }
        else
        {
            dispatcher = iterator->second;
            if (dispatcher->signature->result.name != signature->result.name ||
                dispatcher->signature->arguments.size() != signature->arguments.size())
            {
                throw JSError(runtime, "Native hook signature changed while hooks are active");
            }
            if (method_getImplementation(method) != (IMP) dispatcher->code)
            {
                dispatcher->original = method_getImplementation(method);
                method_setImplementation(method, (IMP) dispatcher->code);
            }
        }
    }

    auto state = std::make_shared<HookState>();
    state->identifier = gNextHookIdentifier.fetch_add(1);
    state->before = std::move(before);
    state->after = std::move(after);
    state->replace = std::move(replace);
    state->cacheOnly = cacheOnly;
    state->once = once;
    state->instanceTarget = instanceTarget;
    state->dispatcher = dispatcher;
    {
        std::lock_guard<std::mutex> lock(gHookMutex);
        dispatcher->hooks.push_back(state);
    }
    return Object::createFromHostObject(runtime, std::make_shared<HookTokenHost>(state));
}

static Value ffiSymbol(Runtime &runtime, const Value *args, size_t count)
{
    if (count == 0 || !args[0].isString())
    {
        throw JSError(runtime, "ffi.symbol expects a symbol name");
    }

    NSString *name = [JSI toNSString:args[0] runtime:runtime];
    void *handle = RTLD_DEFAULT;
    bool closesHandle = false;
    if (count > 1 && args[1].isString())
    {
        NSString *image = [JSI toNSString:args[1] runtime:runtime];
        handle = dlopen(image.UTF8String, RTLD_NOLOAD | RTLD_LAZY);
        if (!handle)
        {
            throw JSError(runtime, "ffi.symbol image is not loaded");
        }
        closesHandle = true;
    }

    void *symbol = dlsym(handle, name.UTF8String);
    if (closesHandle)
    {
        dlclose(handle);
    }
    return pointerResult(runtime, symbol);
}

static Value objcFunction(Runtime &runtime, const Value &target, const Value &selectorValue,
                          const Value *args, size_t count, size_t start)
{
    id object = objcValue(runtime, target);
    NSString *selectorName = [JSI toNSString:selectorValue runtime:runtime];
    if (!object || selectorName.length == 0)
    {
        throw JSError(runtime, "objc.call expects an object handle and selector");
    }

    return invokeObject(runtime, object, NSSelectorFromString(selectorName),
                        argumentArray(runtime, args, count, start));
}

static Value getIvar(Runtime &runtime, const Value *args, size_t count)
{
    if (count < 2)
    {
        throw JSError(runtime, "objc.getIvar expects an object and ivar name");
    }

    id object = objcValue(runtime, args[0]);
    NSString *name = [JSI toNSString:args[1] runtime:runtime];
    Ivar ivar = object ? class_getInstanceVariable(object_getClass(object), name.UTF8String) : NULL;
    if (!ivar)
    {
        return Value::undefined();
    }

    const char *type = ivar_getTypeEncoding(ivar);
    uint8_t *address = (uint8_t *) (__bridge void *) object + ivar_getOffset(ivar);
    char code = normalizedType(type);
    if (!type || !*type)
    {
        return objcResult(runtime, object_getIvar(object, ivar));
    }
    if (code == '@')
    {
        __unsafe_unretained id value = nil;
        memcpy(&value, address, sizeof(value));
        return objcResult(runtime, value);
    }

    if (code == '#')
    {
        Class value = Nil;
        memcpy(&value, address, sizeof(value));
        return objcResult(runtime, value);
    }

    if (code == ':')
    {
        SEL value = NULL;
        memcpy(&value, address, sizeof(value));
        return value ? String::createFromUtf8(runtime, sel_getName(value)) : Value::null();
    }

    if (code == '^' || code == '*')
    {
        void *value = nullptr;
        memcpy(&value, address, sizeof(value));
        return pointerResult(runtime, value);
    }

    if (code == 'B')
    {
        bool value = false;
        memcpy(&value, address, sizeof(value));
        return Value(value);
    }
    if (code == 'f')
    {
        float value = 0;
        memcpy(&value, address, sizeof(value));
        return Value((double) value);
    }
    if (code == 'd')
    {
        double value = 0;
        memcpy(&value, address, sizeof(value));
        return Value(value);
    }
    if (code == 'c')
    {
        int8_t value = 0;
        memcpy(&value, address, sizeof(value));
        return Value((double) value);
    }
    if (code == 'C')
    {
        uint8_t value = 0;
        memcpy(&value, address, sizeof(value));
        return Value((double) value);
    }
    if (code == 's')
    {
        int16_t value = 0;
        memcpy(&value, address, sizeof(value));
        return Value((double) value);
    }
    if (code == 'S')
    {
        uint16_t value = 0;
        memcpy(&value, address, sizeof(value));
        return Value((double) value);
    }
    if (code == 'i')
    {
        int32_t value = 0;
        memcpy(&value, address, sizeof(value));
        return Value((double) value);
    }
    if (code == 'I')
    {
        uint32_t value = 0;
        memcpy(&value, address, sizeof(value));
        return Value((double) value);
    }
    if (code == 'l' || code == 'q')
    {
        int64_t value = 0;
        memcpy(&value, address, sizeof(value));
        return Value(runtime, BigInt::fromInt64(runtime, value));
    }
    if (code == 'L' || code == 'Q')
    {
        uint64_t value = 0;
        memcpy(&value, address, sizeof(value));
        return Value(runtime, BigInt::fromUint64(runtime, value));
    }
    if (code == '{')
    {
        NSUInteger size = 0;
        NSUInteger alignment = 0;
        NSGetSizeAndAlignment(ivar_getTypeEncoding(ivar), &size, &alignment);
        return structResult(runtime, [NSString stringWithUTF8String:type] ?: @"",
                            [NSValue value:address withObjCType:type]);
    }
    throw JSError(runtime, "Unsupported ivar type");
}

static Value setIvar(Runtime &runtime, const Value *args, size_t count)
{
    if (count < 3)
    {
        throw JSError(runtime, "objc.setIvar expects an object, ivar name, and value");
    }

    id object = objcValue(runtime, args[0]);
    NSString *name = [JSI toNSString:args[1] runtime:runtime];
    Ivar ivar = object ? class_getInstanceVariable(object_getClass(object), name.UTF8String) : NULL;
    if (!ivar)
    {
        throw JSError(runtime, "Objective-C ivar is unavailable");
    }

    uint8_t *address = (uint8_t *) (__bridge void *) object + ivar_getOffset(ivar);
    char code = normalizedType(ivar_getTypeEncoding(ivar));
    id value = valueToObjC(runtime, args[2]);
    id scalarValue = value == [NSNull null] ? @0 : value;
    if (code == '@')
    {
        object_setIvar(object, ivar, value == [NSNull null] ? nil : value);
        return Value::undefined();
    }

    if (code == '#')
    {
        Class argument = value != [NSNull null] && object_isClass(value) ? value : Nil;
        memcpy(address, &argument, sizeof(argument));
        return Value::undefined();
    }

    if (code == ':')
    {
        SEL argument = NULL;
        if ([value isKindOfClass:[NSString class]])
        {
            argument = NSSelectorFromString((NSString *) value);
        }
        else if ([value isKindOfClass:[NSValue class]])
        {
            argument = (SEL) [(NSValue *) value pointerValue];
        }
        memcpy(address, &argument, sizeof(argument));
        return Value::undefined();
    }

    if (code == '^' || code == '*')
    {
        void *argument = [value isKindOfClass:[NSValue class]] ? [(NSValue *) value pointerValue] : nullptr;
        memcpy(address, &argument, sizeof(argument));
        return Value::undefined();
    }

    if (code == 'B')
    {
        bool argument = [scalarValue boolValue];
        memcpy(address, &argument, sizeof(argument));
        return Value::undefined();
    }
    if (code == 'f')
    {
        float argument = [scalarValue floatValue];
        memcpy(address, &argument, sizeof(argument));
        return Value::undefined();
    }
    if (code == 'd')
    {
        double argument = [scalarValue doubleValue];
        memcpy(address, &argument, sizeof(argument));
        return Value::undefined();
    }
    if (code == 'c')
    {
        int8_t argument = [scalarValue charValue];
        memcpy(address, &argument, sizeof(argument));
        return Value::undefined();
    }
    if (code == 'C')
    {
        uint8_t argument = [scalarValue unsignedCharValue];
        memcpy(address, &argument, sizeof(argument));
        return Value::undefined();
    }
    if (code == 's')
    {
        int16_t argument = [scalarValue shortValue];
        memcpy(address, &argument, sizeof(argument));
        return Value::undefined();
    }
    if (code == 'S')
    {
        uint16_t argument = [scalarValue unsignedShortValue];
        memcpy(address, &argument, sizeof(argument));
        return Value::undefined();
    }
    if (code == 'i')
    {
        int32_t argument = [scalarValue intValue];
        memcpy(address, &argument, sizeof(argument));
        return Value::undefined();
    }
    if (code == 'I')
    {
        uint32_t argument = [scalarValue unsignedIntValue];
        memcpy(address, &argument, sizeof(argument));
        return Value::undefined();
    }
    if (code == 'l' || code == 'q')
    {
        int64_t argument = [scalarValue longLongValue];
        memcpy(address, &argument, sizeof(argument));
        return Value::undefined();
    }
    if (code == 'L' || code == 'Q')
    {
        uint64_t argument = [scalarValue unsignedLongLongValue];
        memcpy(address, &argument, sizeof(argument));
        return Value::undefined();
    }
    if (code == '{')
    {
        if (![value isKindOfClass:[NSValue class]])
        {
            throw JSError(runtime, "Native struct ivar value expected");
        }
        NSUInteger size = 0;
        NSUInteger alignment = 0;
        NSGetSizeAndAlignment(ivar_getTypeEncoding(ivar), &size, &alignment);
        [(NSValue *) value getValue:address size:size];
        return Value::undefined();
    }
    throw JSError(runtime, "Unsupported ivar type");
}

static objc_AssociationPolicy associationPolicy(Runtime &runtime, const Value *value)
{
    if (!value || !value->isString())
    {
        return OBJC_ASSOCIATION_RETAIN_NONATOMIC;
    }

    NSString *name = [JSI toNSString:*value runtime:runtime];
    if ([name isEqualToString:@"assign"])
    {
        return OBJC_ASSOCIATION_ASSIGN;
    }
    if ([name isEqualToString:@"retain"])
    {
        return OBJC_ASSOCIATION_RETAIN;
    }
    if ([name isEqualToString:@"copy"])
    {
        return OBJC_ASSOCIATION_COPY;
    }
    if ([name isEqualToString:@"copyNonatomic"])
    {
        return OBJC_ASSOCIATION_COPY_NONATOMIC;
    }
    if ([name isEqualToString:@"retainNonatomic"])
    {
        return OBJC_ASSOCIATION_RETAIN_NONATOMIC;
    }
    throw JSError(runtime, "Unsupported native association policy");
}

static void installObjC(Runtime &runtime, Object &objc)
{
    objc.setProperty(runtime, "getClass", makeFunction(
        "getClass", 1, runtime, [](Runtime &rt, const Value &, const Value *args, size_t count) -> Value {
            if (count == 0 || !args[0].isString())
            {
                return Value::null();
            }
            Class cls = NSClassFromString([JSI toNSString:args[0] runtime:rt]);
            return cls ? Object::createFromHostObject(rt, std::make_shared<ObjCHandleHost>((id) cls))
                       : Value::null();
        }));

    objc.setProperty(runtime, "alloc", makeFunction(
        "alloc", 1, runtime, [](Runtime &rt, const Value &, const Value *args, size_t count) -> Value {
            Class cls = count ? classFromValue(rt, args[0]) : Nil;
            if (!cls)
            {
                throw JSError(rt, "objc.alloc expects a class handle or class name");
            }
            id object = [[cls alloc] init];
            return objcResult(rt, object);
        }));

    objc.setProperty(runtime, "className", makeFunction(
        "className", 1, runtime, [](Runtime &rt, const Value &, const Value *args, size_t count) -> Value {
            id object = count ? objcValue(rt, args[0]) : nil;
            if (!object)
            {
                return Value::null();
            }
            Class cls = object_isClass(object) ? object : object_getClass(object);
            return [JSI fromObjC:NSStringFromClass(cls) runtime:rt];
        }));

    objc.setProperty(runtime, "respondsTo", makeFunction(
        "respondsTo", 2, runtime, [](Runtime &rt, const Value &, const Value *args, size_t count) -> Value {
            if (count < 2)
            {
                return Value(false);
            }
            id object = objcValue(rt, args[0]);
            NSString *name = [JSI toNSString:args[1] runtime:rt];
            return Value(object && [object respondsToSelector:NSSelectorFromString(name)]);
        }));

    objc.setProperty(runtime, "call", makeFunction(
        "call", 2, runtime, [](Runtime &rt, const Value &, const Value *args, size_t count) -> Value {
            if (count < 2)
            {
                throw JSError(rt, "objc.call expects an object handle and selector");
            }
            return objcFunction(rt, args[0], args[1], args, count, 2);
        }));

    objc.setProperty(runtime, "callSuper", makeFunction(
        "callSuper", 3, runtime, [](Runtime &rt, const Value &, const Value *args, size_t count) -> Value {
            if (count < 3)
            {
                throw JSError(rt, "objc.callSuper expects an object, class, and selector");
            }
            id object = objcValue(rt, args[0]);
            Class cls = classFromValue(rt, args[1]);
            NSString *selectorName = [JSI toNSString:args[2] runtime:rt];
            return invokeSuperObject(rt, object, cls, NSSelectorFromString(selectorName),
                                     argumentArray(rt, args, count, 3));
        }));

    objc.setProperty(runtime, "invoke", makeFunction(
        "invoke", 3, runtime, [](Runtime &rt, const Value &, const Value *args, size_t count) -> Value {
            if (count < 3 || !args[2].isObject() || !args[2].asObject(rt).isArray(rt))
            {
                throw JSError(rt, "objc.invoke expects an object, selector, and argument array");
            }
            Array array = args[2].asObject(rt).asArray(rt);
            NSMutableArray *arguments = [NSMutableArray arrayWithCapacity:array.size(rt)];
            for (size_t index = 0; index < array.size(rt); index++)
            {
                [arguments addObject:valueToObjC(rt, array.getValueAtIndex(rt, index)) ?: [NSNull null]];
            }
            id object = objcValue(rt, args[0]);
            NSString *selectorName = [JSI toNSString:args[1] runtime:rt];
            return invokeWithThreadPolicy(rt, object, NSSelectorFromString(selectorName), arguments,
                                          count > 3 ? &args[3] : nullptr);
        }));

    objc.setProperty(runtime, "invokeSuper", makeFunction(
        "invokeSuper", 4, runtime, [](Runtime &rt, const Value &, const Value *args, size_t count) -> Value {
            if (count < 4 || !args[3].isObject() || !args[3].asObject(rt).isArray(rt))
            {
                throw JSError(rt, "objc.invokeSuper expects an object, class, selector, and argument array");
            }
            id object = objcValue(rt, args[0]);
            Class cls = classFromValue(rt, args[1]);
            NSString *selectorName = [JSI toNSString:args[2] runtime:rt];
            Array array = args[3].asObject(rt).asArray(rt);
            NSMutableArray *arguments = [NSMutableArray arrayWithCapacity:array.size(rt)];
            for (size_t index = 0; index < array.size(rt); index++)
            {
                [arguments addObject:valueToObjC(rt, array.getValueAtIndex(rt, index)) ?: [NSNull null]];
            }
            return invokeSuperWithThreadPolicy(rt, object, cls, NSSelectorFromString(selectorName), arguments,
                                               count > 4 ? &args[4] : nullptr);
        }));

    objc.setProperty(runtime, "getIvar", makeFunction("getIvar", 2, runtime, getIvar));
    objc.setProperty(runtime, "setIvar", makeFunction("setIvar", 3, runtime, setIvar));

    objc.setProperty(runtime, "createAssociationKey", makeFunction(
        "createAssociationKey", 0, runtime, [](Runtime &rt, const Value &, const Value *, size_t) -> Value {
            return Object::createFromHostObject(rt,
                                                std::make_shared<AssociationKeyHost>([NSObject new]));
        }));

    objc.setProperty(runtime, "getAssociatedObject", makeFunction(
        "getAssociatedObject", 2, runtime, [](Runtime &rt, const Value &, const Value *args, size_t count) -> Value {
            if (count < 2)
            {
                return Value::null();
            }
            id object = objcValue(rt, args[0]);
            if (!args[1].isObject() || !args[1].asObject(rt).isHostObject<AssociationKeyHost>(rt))
            {
                return Value::null();
            }
            const void *key = args[1].asObject(rt).getHostObject<AssociationKeyHost>(rt)->key();
            return objcResult(rt, objc_getAssociatedObject(object, key));
        }));

    objc.setProperty(runtime, "setAssociatedObject", makeFunction(
        "setAssociatedObject", 4, runtime, [](Runtime &rt, const Value &, const Value *args, size_t count) -> Value {
            if (count < 3 || !args[1].isObject() ||
                !args[1].asObject(rt).isHostObject<AssociationKeyHost>(rt))
            {
                throw JSError(rt, "objc.setAssociatedObject expects an object and association key");
            }
            id object = objcValue(rt, args[0]);
            const void *key = args[1].asObject(rt).getHostObject<AssociationKeyHost>(rt)->key();
            id value = valueToObjC(rt, args[2]);
            objc_setAssociatedObject(object, key, value == [NSNull null] ? nil : value,
                                     associationPolicy(rt, count > 3 ? &args[3] : nullptr));
            return Value::undefined();
        }));

    objc.setProperty(runtime, "struct", makeFunction(
        "struct", 2, runtime, [](Runtime &rt, const Value &, const Value *args, size_t count) -> Value {
            if (count < 2 || !args[0].isString())
            {
                throw JSError(rt, "objc.struct expects a name and fields");
            }
            return structValue(rt, [JSI toNSString:args[0] runtime:rt], args[1]);
        }));

    objc.setProperty(runtime, "array", makeFunction(
        "array", 1, runtime, [](Runtime &rt, const Value &, const Value *args, size_t count) -> Value {
            id object = count ? objcValue(rt, args[0]) : nil;
            if (![object isKindOfClass:[NSArray class]])
            {
                return Array(rt, 0);
            }
            NSArray *array = (NSArray *) object;
            Array result(rt, array.count);
            for (NSUInteger index = 0; index < array.count; index++)
            {
                result.setValueAtIndex(rt, index, objcResult(rt, array[index]));
            }
            return result;
        }));

    objc.setProperty(runtime, "data", makeFunction(
        "data", 1, runtime, [](Runtime &rt, const Value &, const Value *args, size_t count) -> Value {
            NSData *data = count ? valueToData(rt, args[0]) : nil;
            if (!data)
            {
                throw JSError(rt, "objc.data expects an ArrayBuffer or TypedArray");
            }
            return objcResult(rt, data);
        }));

    objc.setProperty(runtime, "hook", makeFunction("hook", 3, runtime, makeHook));
}

static void installFFI(Runtime &runtime, Object &ffi)
{
    ffi.setProperty(runtime, "symbol", makeFunction("symbol", 2, runtime, ffiSymbol));
    ffi.setProperty(runtime, "call", makeFunction("call", 3, runtime, ffiCallValue));
}

static void installFabric(Runtime &runtime, Object &fabric)
{
    fabric.setProperty(runtime, "mount", makeFunction("mount", 3, runtime, fabricMount));
    fabric.setProperty(runtime, "update", makeFunction("update", 2, runtime, fabricUpdate));
    fabric.setProperty(runtime, "setSize", makeFunction("setSize", 3, runtime, fabricSetSize));
    fabric.setProperty(runtime, "setFrame", makeFunction("setFrame", 2, runtime, fabricSetFrame));
    fabric.setProperty(runtime, "measure", makeFunction("measure", 1, runtime, fabricMeasure));
    fabric.setProperty(runtime, "unmount", makeFunction("unmount", 1, runtime, fabricUnmount));
}

}

namespace loader {

void setNativePluginRuntimeExecutor(id instance)
{
    gRuntimeExecutorInstance = instance;
}

void setNativePluginFabricHost(id instance)
{
    gFabricHostInstance = instance;
}

void registerNativePluginBridge(Runtime &runtime)
{
    gNativePluginRuntime = &runtime;
    gNativePluginRuntimeThread = std::this_thread::get_id();
    Object bridge(runtime);
    bridge.setProperty(runtime, "apiVersion", String::createFromUtf8(runtime, kNativePluginApiVersion));
    bridge.setProperty(runtime, "abiVersion", String::createFromUtf8(runtime, kNativePluginAbiVersion));

    Array capabilities(runtime, 8);
    const char *names[] = {
        "native.objc.classes",
        "native.objc.invoke",
        "native.objc.ivars",
        "native.objc.associations",
        "native.objc.hooks",
        "native.ffi.symbols",
        "native.ffi.call",
        "native.fabric.mount",
    };
    for (size_t index = 0; index < 8; index++)
    {
        capabilities.setValueAtIndex(runtime, index, String::createFromUtf8(runtime, names[index]));
    }
    bridge.setProperty(runtime, "capabilities", std::move(capabilities));

    Object objc(runtime);
    installObjC(runtime, objc);
    bridge.setProperty(runtime, "objc", std::move(objc));

    Object ffi(runtime);
    installFFI(runtime, ffi);
    bridge.setProperty(runtime, "ffi", std::move(ffi));

    Object fabric(runtime);
    installFabric(runtime, fabric);
    bridge.setProperty(runtime, "fabric", std::move(fabric));

    runtime.global().setProperty(runtime, "NativePlugin", std::move(bridge));
}

}
