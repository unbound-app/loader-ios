#import "NativePluginBridge.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import <algorithm>
#import <atomic>
#import <cstdint>
#import <cstring>
#import <functional>
#import <exception>
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

static FFITypeSpec ffiType(Runtime &runtime, const std::string &name);
static Value ffiResult(Runtime &runtime, const FFITypeSpec &spec, const std::vector<uint8_t> &bytes);

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
        retained.push_back(object == [NSNull null] ? nil : object);
        id argument = retained.back();
        [invocation setArgument:&argument atIndex:index];
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
    std::vector<ffi_type *> ffiTypes;
    std::vector<id> retained;
    types.reserve(arguments.count);
    ffiTypes.reserve(arguments.count + 2);
    retained.reserve(arguments.count);

    struct objc_super superInfo = {target, currentClass};
    values[0].pointer = &superInfo;
    values[1].pointer = selector;
    ffiTypes.push_back(&ffi_type_pointer);
    ffiTypes.push_back(&ffi_type_pointer);
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
        ffiTypes.push_back(types.back().type);
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
    ffi_cif cif{};
    if (ffi_prep_cif(&cif, FFI_DEFAULT_ABI, (unsigned) ffiTypes.size(), result.type, ffiTypes.data()) != FFI_OK)
    {
        throw JSError(runtime, "Native Objective-C super signature could not be prepared");
    }

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

    if (!dispatcher || !gRuntimeExecutorInstance)
    {
        return;
    }

    std::vector<std::shared_ptr<HookState>> hooks;
    {
        std::lock_guard<std::mutex> lock(gHookMutex);
        hooks = dispatcher->hooks;
    }

    for (const std::shared_ptr<HookState> &state : hooks)
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
    {
        std::lock_guard<std::mutex> lock(gHookMutex);
        dispatcher->hooks.push_back(state);
    }
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
