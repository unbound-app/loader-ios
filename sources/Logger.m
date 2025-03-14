#import "Logger.h"

@implementation Logger

static dispatch_queue_t _logQueue;

+ (void)initialize
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _logQueue = dispatch_queue_create("app.unbound", DISPATCH_QUEUE_SERIAL);
    });
}

static os_log_t getLoggerForCategory(const char *category)
{
    static NSMutableDictionary<NSString *, os_log_t> *loggers = nil;
    static dispatch_once_t                            onceToken;

    dispatch_once(&onceToken, ^{ loggers = [NSMutableDictionary dictionary]; });

    NSString *categoryKey = [NSString stringWithUTF8String:category];
    os_log_t  logger      = nil;

    @synchronized(loggers)
    {
        logger = [loggers objectForKey:categoryKey];

        if (!logger)
        {
            logger = os_log_create("app.unbound", category);
            if (logger)
            {
                [loggers setObject:logger forKey:categoryKey];
            }
        }
    }

    return logger ?: OS_LOG_DEFAULT;
}

+ (void)log:(LogLevel)level category:(const char *)category format:(NSString *)format, ...
{
    // Ensure logger is initialized
    [self initialize];

    // Create a copy of the arguments to use in the async block
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    // Get category info
    NSString *categoryStr       = [NSString stringWithUTF8String:category];
    BOOL      isDefaultCategory = [categoryStr isEqualToString:@"default"];

    // Format the final message
    if (isDefaultCategory)
    {
        message = [NSString stringWithFormat:@"[Unbound] %@", message];
    }
    else
    {
        if (categoryStr.length > 0)
        {
            NSString *firstChar = [[categoryStr substringToIndex:1] uppercaseString];
            NSString *restOfStr = categoryStr.length > 1 ? [categoryStr substringFromIndex:1] : @"";
            categoryStr         = [firstChar stringByAppendingString:restOfStr];
        }

        message = [NSString stringWithFormat:@"[Unbound] [%@] %@", categoryStr, message];
    }

    // Get the logger for this category
    os_log_t logger = getLoggerForCategory(category);

    // Log on the background thread to avoid UI freezes
    dispatch_async(_logQueue, ^{
        switch (level)
        {
            case LogLevelDebug:
                os_log_debug(logger, "%{public}@", message);
                break;
            case LogLevelInfo:
                os_log_info(logger, "%{public}@", message);
                break;
            case LogLevelNotice:
                os_log(logger, "%{public}@", message);
                break;
            case LogLevelError:
                os_log_error(logger, "%{public}@", message);
#ifndef DEBUG
                NSLog(@"ERROR: %@", message); // Fallback in release mode
#endif
                break;
            case LogLevelFault:
                os_log_fault(logger, "%{public}@", message);
#ifndef DEBUG
                NSLog(@"FAULT: %@", message); // Fallback in release mode
#endif
                break;
        }
    });
}

+ (void)debug:(const char *)category format:(NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    [self log:LogLevelDebug category:category format:@"%@", message];
}

+ (void)info:(const char *)category format:(NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    [self log:LogLevelInfo category:category format:@"%@", message];
}

+ (void)notice:(const char *)category format:(NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    [self log:LogLevelNotice category:category format:@"%@", message];
}

+ (void)error:(const char *)category format:(NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    [self log:LogLevelError category:category format:@"%@", message];
}

+ (void)fault:(const char *)category format:(NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    [self log:LogLevelFault category:category format:@"%@", message];
}

@end
