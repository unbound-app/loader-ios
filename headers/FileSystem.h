#import "Unbound.h"

// A vnode watch on a single file's inode. In-place writes fire its event directly; an
// atomic/replacing write (write-temp + rename, or delete + recreate) swaps the inode, so the
// source goes silent and is re-armed by the parent DirectoryWatcher on the new inode.
@interface FileMonitor : NSObject
@property (copy) NSString           *path;
@property (copy) dispatch_block_t    onChange;
@property (strong) dispatch_source_t fileSource;
@property (strong) dispatch_source_t debounceTimer;
@property (strong) dispatch_queue_t  queue;
@end

// A single vnode watch shared by every FileMonitor living in the same parent directory. The kernel
// event doesn't name the changed file, so it fans out to all monitors under the directory; this is
// the only signal that catches inode-swapping writes the per-file source can't see.
@interface DirectoryWatcher : NSObject
@property (copy) NSString                   *path;
@property (strong) dispatch_source_t         source;
@property (strong) NSMutableSet<NSString *> *files;
@end

@interface FileSystem : NSObject
{
    NSFileManager *manager;
    NSString      *documents;
}

+ (BOOL)createDirectory:(NSString *)path;
+ (void)writeFile:(NSString *)path contents:(NSData *)contents;

+ (id)delete:(NSString *)path;

+ (NSHTTPURLResponse *)download:(NSURL *)url
                           path:(NSString *)path
                    withHeaders:(NSDictionary *)headers;
+ (NSHTTPURLResponse *)download:(NSURL *)url path:(NSString *)path;

+ (void)monitor:(NSString *)filePath onChange:(void (^)())onChange autoRestart:(BOOL)autoRestart;
+ (void)stopMonitoring:(NSString *)path;

+ (DirectoryWatcher *)watcherForDirectory:(NSString *)dirPath queue:(dispatch_queue_t)queue;
+ (void)releaseDirectoryWatcherFor:(NSString *)dirPath;
+ (void)handleDirectoryEvent:(NSString *)dirPath;
+ (void)armFileSource:(FileMonitor *)monitor;
+ (void)scheduleNotify:(FileMonitor *)monitor;

+ (NSArray *)readDirectory:(NSString *)path;
+ (NSData *)readFile:(NSString *)path;

+ (BOOL)isDirectory:(NSString *)path;
+ (BOOL)exists:(NSString *)path;

+ (void)init;

+ (NSString *)documents;

@end
