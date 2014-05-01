//
// Copyright (c) 2014 Mixpanel. All rights reserved.

#import "MPABTestDesignerConnection.h"
#import "MPABTestDesignerMessage.h"
#import "MPABTestDesignerSnapshotResponseMessage.h"
#import "MPABTestDesignerSnapshotRequestMessage.h"
#import "MPABTestDesignerChangeRequestMessage.h"
#import "MPABTestDesignerDeviceInfoRequestMessage.h"

@interface MPABTestDesignerConnection () <MPWebSocketDelegate>
@end

@implementation MPABTestDesignerConnection
{
    NSMutableDictionary *_session;
    NSDictionary *_typeToMessageClassMap;
    MPWebSocket *_webSocket;
    NSOperationQueue *_commandQueue;
}

- (id)initWithURL:(NSURL *)url
{
    self = [super init];
    if (self)
    {
        _typeToMessageClassMap = @{
            MPABTestDesignerSnapshotRequestMessageType   : [MPABTestDesignerSnapshotRequestMessage class],
            MPABTestDesignerChangeRequestMessageType     : [MPABTestDesignerChangeRequestMessage class],
            MPABTestDesignerDeviceInfoRequestMessageType : [MPABTestDesignerDeviceInfoRequestMessage class],
        };

        _session = [[NSMutableDictionary alloc] init];
        _webSocket = [[MPWebSocket alloc] initWithURL:url];
        _webSocket.delegate = self;

        _commandQueue = [[NSOperationQueue alloc] init];
        _commandQueue.maxConcurrentOperationCount = 1;
        _commandQueue.suspended = YES;

        NSLog(@"Attempting to open WebSocket to: %@", url);
        [_webSocket open];
    }
    
    return self;
}

- (void)dealloc
{
    _webSocket.delegate = nil;
    [_webSocket close];
}

- (void)setSessionObject:(id)object forKey:(NSString *)key
{
    NSParameterAssert(key != nil);

    @synchronized (_session)
    {
        _session[key] = object ?: [NSNull null];
    }
}

- (id)sessionObjectForKey:(NSString *)key
{
    NSParameterAssert(key != nil);

    @synchronized (_session)
    {
        id object = _session[key];
        return [object isEqual:[NSNull null]] ? nil : object;
    }
}

- (void)sendMessage:(id<MPABTestDesignerMessage>)message
{
    NSLog(@"Sending message: %@", [message debugDescription]);
    NSString *jsonString = [[NSString alloc] initWithData:[message JSONData] encoding:NSUTF8StringEncoding];
    [_webSocket send:jsonString];
}

- (id <MPABTestDesignerMessage>)designerMessageForMessage:(id)message
{
    NSLog(@"raw message: %@", message);

    NSParameterAssert([message isKindOfClass:[NSString class]] || [message isKindOfClass:[NSData class]]);

    id <MPABTestDesignerMessage> designerMessage = nil;

    NSData *jsonData = [message isKindOfClass:[NSString class]] ? [(NSString *)message dataUsingEncoding:NSUTF8StringEncoding] : message;

    NSError *error = nil;
    id jsonObject = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    if ([jsonObject isKindOfClass:[NSDictionary class]])
    {
        NSDictionary *messageDictionary = (NSDictionary *)jsonObject;
        NSString *type = messageDictionary[@"type"];
        NSDictionary *payload = messageDictionary[@"payload"];

        designerMessage = [_typeToMessageClassMap[type] messageWithType:type payload:payload];
    }
    else
    {
        NSLog(@"Badly formed socket message expected JSON dictionary: %@", error);
    }

    return designerMessage;
}

#pragma mark - MPWebSocketDelegate Methods

- (void)webSocket:(MPWebSocket *)webSocket didReceiveMessage:(id)message
{
    id<MPABTestDesignerMessage> designerMessage = [self designerMessageForMessage:message];
    NSLog(@"WebSocket received message: %@", [designerMessage debugDescription]);

    NSOperation *commandOperation = [designerMessage responseCommandWithConnection:self];

    if (commandOperation)
    {
        [_commandQueue addOperation:commandOperation];
    }
}

- (void)webSocketDidOpen:(MPWebSocket *)webSocket
{
    NSLog(@"WebSocket did open.");
    self.connected = YES;
    _commandQueue.suspended = NO;
}

- (void)webSocket:(MPWebSocket *)webSocket didFailWithError:(NSError *)error
{
    NSLog(@"WebSocket did fail with error: %@", error);
    _commandQueue.suspended = YES;
    [_commandQueue cancelAllOperations];

    self.connected = NO;
}

- (void)webSocket:(MPWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean
{
    NSLog(@"WebSocket did close with code '%d' reason '%@'.", (int)code, reason);

    _commandQueue.suspended = YES;
    [_commandQueue cancelAllOperations];

    self.connected = NO;
}

@end

