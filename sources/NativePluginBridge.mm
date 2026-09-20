#import "NativePluginBridge.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import <algorithm>
#import <atomic>
#import <cstdint>
#import <cstring>
#import <functional>
#import <memory>
#import <mutex>
#import <sstream>
#import <string>
#import <unordered_map>
#import <vector>

#import "JSI.h"
#import "Logger.h"
#import "NativePluginFFI.h"

using namespace facebook;
using namespace facebook::jsi;

@interface NSObject (UnboundRuntimeExecutor)
- (void)callFunctionOnBufferedRuntimeExecutor:
    (std::function<void(facebook::jsi::Runtime &)> &&)executor;
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

class StructHost final : public HostObject
{
public:
    StructHost(NSString *name, NSValue *value) : name_([name copy]), value_(value) {}

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

struct HookState;

struct HookDispatcher {
    Class cls;
    SEL selector;
    IMP original;
    std::vector<std::shared_ptr<HookState>> hooks;
};

struct HookState {
    uint64_t identifier;
    std::shared_ptr<Function> after;
    std::weak_ptr<HookDispatcher> dispatcher;
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

static std::mutex gFFIMutex;
static std::unordered_map<std::string, std::shared_ptr<FFITypeDefinition>> gFFITypes;

static void dispatchVoidHook(id object, SEL selector);

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

    if ([value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSArray class]] ||
        [value isKindOfClass:[NSDictionary class]])
    {
        return [JSI fromObjC:value runtime:runtime];
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

    if (code == 'c' || code == 'C')
    {
        unsigned char value = 0;
        [invocation getReturnValue:&value];
        return Value((double) value);
    }

    if (code == 's' || code == 'S')
    {
        unsigned short value = 0;
        [invocation getReturnValue:&value];
        return Value((double) value);
    }

    if (code == 'i' || code == 'I' || code == 'l' || code == 'L')
    {
        unsigned long value = 0;
        [invocation getReturnValue:&value];
        return Value((double) value);
    }

    if (code == 'q')
    {
        long long value = 0;
        [invocation getReturnValue:&value];
        return Value(runtime, BigInt::fromInt64(runtime, value));
    }

    if (code == 'Q')
    {
        unsigned long long value = 0;
        [invocation getReturnValue:&value];
        return Value(runtime, BigInt::fromUint64(runtime, value));
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

    if (code == '@' || code == '#' || code == ':')
    {
        retained.push_back(object == [NSNull null] ? nil : object);
        id argument = retained.back();
        [invocation setArgument:&argument atIndex:index];
        return;
    }

    if (code == '^' || code == '*')
    {
        void *pointer = [object isKindOfClass:[NSValue class]] ? [(NSValue *) object pointerValue] : nullptr;
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

    if (code == 'c' || code == 'C' || code == 's' || code == 'S' || code == 'i' || code == 'I' ||
        code == 'l' || code == 'L')
    {
        long long argument = [object respondsToSelector:@selector(longLongValue)] ? [object longLongValue] : 0;
        storage.emplace_back(sizeof(long long));
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

    std::shared_ptr<HookDispatcher> dispatcher = state->dispatcher.lock();
    if (!dispatcher)
    {
        return;
    }

    std::lock_guard<std::mutex> lock(gHookMutex);
    auto iterator = std::find(dispatcher->hooks.begin(), dispatcher->hooks.end(), state);
    if (iterator != dispatcher->hooks.end())
    {
        dispatcher->hooks.erase(iterator);
    }

    if (!dispatcher->hooks.empty())
    {
        return;
    }

    Method method = class_getInstanceMethod(dispatcher->cls, dispatcher->selector);
    if (method && method_getImplementation(method) == (IMP) dispatchVoidHook)
    {
        method_setImplementation(method, dispatcher->original);
    }

    gDispatchers.erase(hookKey(dispatcher->cls, dispatcher->selector));
}

static void dispatchVoidHook(id object, SEL selector)
{
    std::shared_ptr<HookDispatcher> dispatcher;
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
        if (iterator != gDispatchers.end())
        {
            dispatcher = iterator->second;
        }
    }

    if (dispatcher && dispatcher->original)
    {
        ((void (*)(id, SEL)) dispatcher->original)(object, selector);
    }

    if (!dispatcher || dispatcher->hooks.empty() || !gRuntimeExecutorInstance)
    {
        return;
    }

    for (const std::shared_ptr<HookState> &state : dispatcher->hooks)
    {
        if (!state->active || !state->after)
        {
            continue;
        }

        id retainedObject = object;
        std::shared_ptr<Function> callback = state->after;
        [gRuntimeExecutorInstance callFunctionOnBufferedRuntimeExecutor:
            [retainedObject, selector, callback](Runtime &runtime) {
                try
                {
                    Object context(runtime);
                    context.setProperty(runtime, "self",
                                        Object::createFromHostObject(
                                            runtime, std::make_shared<ObjCHandleHost>(retainedObject)));
                    context.setProperty(runtime, "selector",
                                        String::createFromUtf8(runtime, sel_getName(selector)));
                    context.setProperty(runtime, "args", Array(runtime, 0));
                    callback->call(runtime, context);
                }
                catch (const std::exception &exception)
                {
                    [Logger error:LOG_CATEGORY_PLUGINAPI
                            format:@"Native plugin hook failed: %s", exception.what()];
                }
            }];
    }
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
    return Value::undefined();
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

    const char *encoding = method_getTypeEncoding(method);
    if (normalizedType(encoding) != 'v' || method_getNumberOfArguments(method) != 2)
    {
        throw JSError(runtime, "v@:-only hooks are supported in native plugin ABI v1");
    }

    Object handlers = args[2].asObject(runtime);
    Value afterValue = handlers.getProperty(runtime, "after");
    if (!afterValue.isObject() || !afterValue.asObject(runtime).isFunction(runtime))
    {
        throw JSError(runtime, "objc.hook requires an after handler for v@ selectors");
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
            method_setImplementation(method, (IMP) dispatchVoidHook);
            gDispatchers[key] = dispatcher;
        }
        else
        {
            dispatcher = iterator->second;
        }
    }

    auto state = std::make_shared<HookState>();
    state->identifier = gNextHookIdentifier.fetch_add(1);
    state->after = std::make_shared<Function>(afterValue.asObject(runtime).getFunction(runtime));
    state->dispatcher = dispatcher;
    dispatcher->hooks.push_back(state);
    return Object::createFromHostObject(runtime, std::make_shared<HookTokenHost>(state));
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
    return nullptr;
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

    if (spec.name == "pointer" || spec.name == "object" || spec.name == "class" ||
        spec.name == "selector")
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
    if (spec.name == "object" || spec.name == "class" || spec.name == "selector")
    {
        __unsafe_unretained id object = nil;
        memcpy(&object, bytes.data(), sizeof(object));
        return objcResult(runtime, object);
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
    std::vector<ffi_type *> argumentTypes;
    std::vector<FFICallArgument> arguments(signature.arguments.size());
    std::vector<void *> argumentValues(signature.arguments.size());
    argumentTypes.reserve(signature.arguments.size());
    for (size_t index = 0; index < signature.arguments.size(); index++)
    {
        argumentTypes.push_back(signature.arguments[index].type);
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

    ffi_cif cif{};
    if (ffi_prep_cif(&cif, FFI_DEFAULT_ABI, (unsigned) argumentTypes.size(), signature.result.type,
                     argumentTypes.data()) != FFI_OK)
    {
        throw JSError(runtime, "Native FFI signature could not be prepared");
    }

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
    if (code == '@')
    {
        __unsafe_unretained id value = nil;
        memcpy(&value, address, sizeof(value));
        return objcResult(runtime, value);
    }
    if (code == 'B')
    {
        return Value(*(bool *) address);
    }
    if (code == 'f')
    {
        return Value((double) *(float *) address);
    }
    if (code == 'd')
    {
        return Value(*(double *) address);
    }
    if (code == 'q' || code == 'Q')
    {
        long long value = *(long long *) address;
        return code == 'q' ? Value(runtime, BigInt::fromInt64(runtime, value))
                           : Value(runtime, BigInt::fromUint64(runtime, (uint64_t) value));
    }
    if (code == 'i' || code == 'l' || code == 's' || code == 'c')
    {
        return Value((double) *(long long *) address);
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
    if (code == '@')
    {
        object_setIvar(object, ivar, value == [NSNull null] ? nil : value);
        return Value::undefined();
    }
    if (code == 'B')
    {
        *(bool *) address = [value boolValue];
        return Value::undefined();
    }
    if (code == 'f')
    {
        *(float *) address = [value floatValue];
        return Value::undefined();
    }
    if (code == 'd')
    {
        *(double *) address = [value doubleValue];
        return Value::undefined();
    }
    if (code == 'q' || code == 'Q' || code == 'i' || code == 'l' || code == 's' || code == 'c')
    {
        *(long long *) address = [value longLongValue];
        return Value::undefined();
    }
    throw JSError(runtime, "Unsupported ivar type");
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
        "callSuper", 3, runtime, [](Runtime &rt, const Value &, const Value *, size_t) -> Value {
            throw JSError(rt, "objc.callSuper is not available in ABI v1");
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
            return invokeObject(rt, object, NSSelectorFromString(selectorName), arguments);
        }));

    objc.setProperty(runtime, "invokeSuper", makeFunction(
        "invokeSuper", 4, runtime, [](Runtime &rt, const Value &, const Value *, size_t) -> Value {
            throw JSError(rt, "objc.invokeSuper is not available in ABI v1");
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
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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

}

namespace unbound {

void setNativePluginRuntimeExecutor(id instance)
{
    gRuntimeExecutorInstance = instance;
}

void registerNativePluginBridge(Runtime &runtime)
{
    Object bridge(runtime);
    bridge.setProperty(runtime, "apiVersion", String::createFromUtf8(runtime, kNativePluginApiVersion));
    bridge.setProperty(runtime, "abiVersion", String::createFromUtf8(runtime, kNativePluginAbiVersion));

    Array capabilities(runtime, 7);
    const char *names[] = {
        "native.objc.classes",
        "native.objc.invoke",
        "native.objc.ivars",
        "native.objc.associations",
        "native.objc.hooks",
        "native.ffi.symbols",
        "native.ffi.call",
    };
    for (size_t index = 0; index < 7; index++)
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

    runtime.global().setProperty(runtime, "UnboundNativePlugin", std::move(bridge));
}

}
