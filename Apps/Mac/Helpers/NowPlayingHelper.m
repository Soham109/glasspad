// Glasspad now-playing helper.
//
// Since macOS 15.4, MediaRemote.framework only answers now-playing queries from Apple processes
// (bundle ids starting with "com.apple."), so Glasspad itself gets nothing back. /usr/bin/perl is
// such a process (com.apple.perl) and does not enforce library validation, so Glasspad starts
//
//     /usr/bin/perl -e <loader> /path/to/GlasspadNowPlaying.dylib
//
// where the loader uses DynaLoader to load this library and call `glasspad_nowplaying_run` as
// an XSUB. Everything below then runs inside perl and may use MediaRemote freely.
//
// The approach comes from mediaremote-adapter by Jonas van den Berg and contributors
// (https://github.com/ungive/mediaremote-adapter, BSD 3-Clause License). This file is an
// independent, smaller reimplementation; its JSON output follows that project's stream format
// ({"type":"data","diff":false,"payload":{...}} with the same payload key names, times in
// microseconds as with its --micros option) so either producer can feed Glasspad's parser.
//
// Protocol:
//   stdout: one JSON object per line. "payload" is null when nothing is playing.
//           {"type":"error","message":"..."} when MediaRemote cannot be used.
//   stdin:  one command per line: "send <MRCommand>", "seek <seconds>", "shuffle <1-3>",
//           "repeat <1-3>", "refresh". End of input (Glasspad quit) exits the process, and so
//           does Glasspad's exit itself (watched by pid, in case the pipe stays open).

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>

typedef bool (*SendCommandFn)(int command, id userInfo);
typedef void (*SetElapsedTimeFn)(double elapsed);
typedef void (*SetModeFn)(int mode);
typedef void (*RegisterFn)(dispatch_queue_t queue);
typedef void (*GetPIDFn)(dispatch_queue_t queue, void (^completion)(int pid));
typedef void (*GetClientFn)(dispatch_queue_t queue, void (^completion)(id client));
typedef void (*GetInfoFn)(dispatch_queue_t queue, void (^completion)(NSDictionary *info));
typedef void (*GetIsPlayingFn)(dispatch_queue_t queue, void (^completion)(bool playing));

static SendCommandFn gSendCommand;
static SetElapsedTimeFn gSetElapsedTime;
static SetModeFn gSetShuffleMode;
static SetModeFn gSetRepeatMode;
static GetPIDFn gGetPID;
static GetClientFn gGetClient;
static GetInfoFn gGetInfo;
static GetIsPlayingFn gGetIsPlaying;

static dispatch_queue_t gQueue;
static NSString *gLastLine;
static NSData *gLastArtwork;
static NSString *gLastArtworkBase64;
static BOOL gRefreshScheduled;
static dispatch_source_t gParentWatch;

static void emitLine(NSString *line) {
    if ([line isEqualToString:gLastLine]) return;
    gLastLine = line;
    fputs(line.UTF8String, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void emitJSON(NSDictionary *object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (data == nil) return;
    emitLine([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
}

static void fail(NSString *message) {
    emitJSON(@{@"type" : @"error", @"message" : message});
    exit(2);
}

/// Copies a value into the payload when it is JSON-friendly.
static void put(NSMutableDictionary *payload, NSString *key, id value) {
    if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) payload[key] = value;
}

static NSNumber *micros(id seconds) {
    if (![seconds isKindOfClass:NSNumber.class]) return nil;
    return @(floor([seconds doubleValue] * 1000000.0));
}

static void refreshNow(void) {
    __block int pid = 0;
    __block id client = nil;
    __block BOOL playing = NO;
    __block NSDictionary *info = nil;
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    gGetPID(gQueue, ^(int p) { pid = p; dispatch_group_leave(group); });
    dispatch_group_enter(group);
    gGetClient(gQueue, ^(id c) { client = c; dispatch_group_leave(group); });
    dispatch_group_enter(group);
    gGetIsPlaying(gQueue, ^(bool p) { playing = p; dispatch_group_leave(group); });
    dispatch_group_enter(group);
    gGetInfo(gQueue, ^(NSDictionary *i) { info = i; dispatch_group_leave(group); });
    dispatch_group_notify(group, gQueue, ^{
      NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
      if (info == nil || ![title isKindOfClass:NSString.class] || title.length == 0) {
          emitJSON(@{@"type" : @"data", @"diff" : @NO, @"payload" : NSNull.null});
          return;
      }
      NSMutableDictionary *p = [NSMutableDictionary dictionary];
      p[@"playing"] = @(playing);
      if (pid > 0) {
          p[@"processIdentifier"] = @(pid);
          NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
          put(p, @"bundleIdentifier", app.bundleIdentifier);
          put(p, @"applicationName", app.localizedName);
      }
      if ([client respondsToSelector:@selector(bundleIdentifier)] && p[@"bundleIdentifier"] == nil) {
          put(p, @"bundleIdentifier", [client performSelector:@selector(bundleIdentifier)]);
      }
      if ([client respondsToSelector:@selector(parentApplicationBundleIdentifier)]) {
          put(p, @"parentApplicationBundleIdentifier",
              [client performSelector:@selector(parentApplicationBundleIdentifier)]);
      }
      if ([client respondsToSelector:@selector(displayName)] && p[@"applicationName"] == nil) {
          put(p, @"applicationName", [client performSelector:@selector(displayName)]);
      }
      put(p, @"title", title);
      put(p, @"artist", info[@"kMRMediaRemoteNowPlayingInfoArtist"]);
      put(p, @"album", info[@"kMRMediaRemoteNowPlayingInfoAlbum"]);
      put(p, @"playbackRate", info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]);
      put(p, @"shuffleMode", info[@"kMRMediaRemoteNowPlayingInfoShuffleMode"]);
      put(p, @"repeatMode", info[@"kMRMediaRemoteNowPlayingInfoRepeatMode"]);
      put(p, @"uniqueIdentifier", info[@"kMRMediaRemoteNowPlayingInfoUniqueIdentifier"]);
      put(p, @"durationMicros", micros(info[@"kMRMediaRemoteNowPlayingInfoDuration"]));
      put(p, @"elapsedTimeMicros", micros(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]));
      id timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
      if ([timestamp isKindOfClass:NSDate.class]) {
          p[@"timestampEpochMicros"] = @(floor([timestamp timeIntervalSince1970] * 1000000.0));
      }
      NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
      if ([artwork isKindOfClass:NSData.class] && artwork.length > 0) {
          // Base64 of the same image is reused rather than recomputed on every update.
          if (![artwork isEqualToData:gLastArtwork]) {
              gLastArtwork = artwork;
              gLastArtworkBase64 = [artwork base64EncodedStringWithOptions:0];
          }
          p[@"artworkData"] = gLastArtworkBase64;
          put(p, @"artworkMimeType", info[@"kMRMediaRemoteNowPlayingInfoArtworkMIMEType"]);
      }
      emitJSON(@{@"type" : @"data", @"diff" : @NO, @"payload" : p});
    });
}

/// Notifications often come in bursts; one refresh 60 ms after the first covers them all.
static void scheduleRefresh(void) {
    dispatch_async(gQueue, ^{
      if (gRefreshScheduled) return;
      gRefreshScheduled = YES;
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_MSEC), gQueue, ^{
        gRefreshScheduled = NO;
        refreshNow();
      });
    });
}

static void handleCommand(NSString *line) {
    NSArray<NSString *> *parts = [line componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (parts.count == 0) return;
    NSString *verb = parts[0];
    double arg = parts.count > 1 ? parts[1].doubleValue : 0;
    if ([verb isEqualToString:@"send"] && parts.count > 1) {
        gSendCommand((int)arg, nil);
    } else if ([verb isEqualToString:@"seek"] && parts.count > 1 && gSetElapsedTime) {
        gSetElapsedTime(MAX(0, arg));
    } else if ([verb isEqualToString:@"shuffle"] && parts.count > 1 && gSetShuffleMode) {
        gSetShuffleMode((int)arg);
    } else if ([verb isEqualToString:@"repeat"] && parts.count > 1 && gSetRepeatMode) {
        gSetRepeatMode((int)arg);
    } else if ([verb isEqualToString:@"refresh"]) {
        // Forget the last line so the full state is printed again.
        dispatch_async(gQueue, ^{ gLastLine = nil; });
    }
    scheduleRefresh();
}

static void readCommands(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      char *buffer = NULL;
      size_t capacity = 0;
      ssize_t length;
      while ((length = getline(&buffer, &capacity, stdin)) > 0) {
          NSString *line = [[[NSString alloc] initWithBytes:buffer length:(NSUInteger)length encoding:NSUTF8StringEncoding]
              stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
          if (line.length > 0) dispatch_async(gQueue, ^{ handleCommand(line); });
      }
      // Glasspad closed the pipe (quit or crashed): stop too.
      exit(0);
    });
}

/// Exits when Glasspad (the parent) exits, even if something else still holds the stdin pipe
/// open. Glasspad gone before the watch starts shows as a parent pid of 1 (launchd).
static void watchParent(void) {
    pid_t parent = getppid();
    if (parent <= 1) exit(0);
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)parent, DISPATCH_PROC_EXIT,
                                                      dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_event_handler(source, ^{ exit(0); });
    dispatch_resume(source);
    gParentWatch = source;
    if (getppid() != parent) exit(0);
}

/// Entry point, called by perl as an XSUB. The two arguments (perl interpreter, CV) are unused.
/// Never returns.
__attribute__((visibility("default"))) void glasspad_nowplaying_run(void *perl, void *cv) {
    (void)perl;
    (void)cv;
    @autoreleasepool {
        void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (mr == NULL) fail(@"MediaRemote.framework did not load");
        gSendCommand = (SendCommandFn)dlsym(mr, "MRMediaRemoteSendCommand");
        gSetElapsedTime = (SetElapsedTimeFn)dlsym(mr, "MRMediaRemoteSetElapsedTime");
        gSetShuffleMode = (SetModeFn)dlsym(mr, "MRMediaRemoteSetShuffleMode");
        gSetRepeatMode = (SetModeFn)dlsym(mr, "MRMediaRemoteSetRepeatMode");
        RegisterFn registerFn = (RegisterFn)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
        gGetPID = (GetPIDFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationPID");
        gGetClient = (GetClientFn)dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
        gGetInfo = (GetInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
        gGetIsPlaying = (GetIsPlayingFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        if (!gSendCommand || !registerFn || !gGetPID || !gGetClient || !gGetInfo || !gGetIsPlaying) {
            fail(@"MediaRemote is missing a function Glasspad needs");
        }
        gQueue = dispatch_queue_create("glasspad.nowplaying", DISPATCH_QUEUE_SERIAL);

        NSArray<NSString *> *names = @[
            @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationClientStateDidChange",
        ];
        for (NSString *name in names) {
            [NSNotificationCenter.defaultCenter addObserverForName:name
                                                            object:nil
                                                             queue:nil
                                                        usingBlock:^(NSNotification *note) { scheduleRefresh(); }];
        }
        [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidTerminateApplicationNotification
                                                                    object:nil
                                                                     queue:nil
                                                                usingBlock:^(NSNotification *note) { scheduleRefresh(); }];
        registerFn(gQueue);

        // Some players change position without a notification; a slow refresh catches that.
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQueue);
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 5 * NSEC_PER_SEC, NSEC_PER_SEC / 2);
        dispatch_source_set_event_handler(timer, ^{ refreshNow(); });
        dispatch_resume(timer);

        readCommands();
        watchParent();
    }
    CFRunLoopRun();
    exit(0);
}
