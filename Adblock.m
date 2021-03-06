#import "Adblock.h"
#import <JavaScriptCore/JavaScriptCore.h>
#import "NSURL+Matcher.h"

@interface Adblock()
@property (nonatomic, strong) JSContext* jscontext;
@property (nonatomic, strong) JSManagedValue* funcShouldBlock;
@property (atomic, strong) NSMutableSet* replacedUrls;

@end

@implementation Adblock

+ (instancetype)singleton
{
  static Adblock* instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[self alloc] init];
  });
  return instance;
}

- (NSString*)stringForFile:(NSString*)name
{
  name = [@"adblock-resources/" stringByAppendingString:name];
  NSString* filePath = [[NSBundle mainBundle] pathForResource:name ofType:@"txt"];
  assert(filePath);

  NSError* error = nil;
  NSString* content = [NSString stringWithContentsOfFile:filePath
                                                encoding:NSUTF8StringEncoding
                                                   error:&error];
  assert(!error);
  return content;
}

-(void)loadJS:(NSString*)name
{
  NSString* script = [self stringForFile:name];
  assert(script);
  [self.jscontext evaluateScript:script];
  NSLog(@"%@", self.jscontext.exception);
  assert(self.jscontext.exception == nil);
}

- (instancetype)init
{
  if (self = [super init]) {
    self.replacedUrls = [NSMutableSet set];

    self.jscontext = [[JSContext alloc] init];

    [self loadJS:@"polyfills.js"];
    [self loadJS:@"abp.js"];
    [self loadJS:@"abp-ios-wrapper.js"];

    JSValue* val = self.jscontext[@"loadList"];
    assert(val);
    NSString* str = [self stringForFile:@"easylist"];
    //NSLog(@"%@", self.jscontext.exception);
    assert(self.jscontext.exception == nil);
    val = [val callWithArguments:[NSArray arrayWithObject:str]];
    //NSLog(@"%@ %@", self.jscontext.exception, val);

    self.funcShouldBlock = [JSManagedValue managedValueWithValue:
                            self.jscontext[@"shouldBlock"]];
    [self.jscontext.virtualMachine addManagedReference:self.funcShouldBlock withOwner:self];
  }
  return self;
}

int callcount = 0;
- (BOOL)shouldBlock:(NSURLRequest*)request
{
  @synchronized(self){
    static BOOL ranonce = NO;
    static NSMutableDictionary* cachedResults;
    if (!ranonce) {
      ranonce = YES;
      cachedResults = [NSMutableDictionary dictionary];
    }

    if ([request.mainDocumentURL.host isEqualToString:request.URL.host]) {
      // this only stops 1% of checks, not useful
      return NO;
    }

    NSString* url = request.URL.absoluteString;
    NSString* domain = request.URL.host;

    NSNumber* obj = cachedResults[url];
    if (obj) {
      return [obj boolValue];
    }

    JSValue* val = [self.funcShouldBlock.value callWithArguments:[NSArray arrayWithObjects:url, domain, nil]];
    //NSLog(@"%@ %@", self.jscontext.exception, val);

    BOOL block = [val toBool];
    if (block) {
   //   NSLog(@"block");
      [self.replacedUrls addObject:request.URL];
    }

    callcount++;
    //NSLog(@"%d", callcount);

    cachedResults[url] = [NSNumber numberWithBool:block];
    return block;
  }
}

- (NSString*)getBlockedAsString
{
  if (self.replacedUrls.count < 1)
    return @"[]";

  NSMutableString* result = [NSMutableString stringWithString:@"["];
  for (NSURL* url in self.replacedUrls) {
    [result appendFormat:@"'%@',", url.absoluteString];
  }
  [result deleteCharactersInRange:NSMakeRange(result.length - 1, 1)];
  [result appendString:@"]"];
  return result;
}


- (BOOL)isAlreadyBlockedUrl:(NSURL*)url
{
  for (NSURL* replaced in self.replacedUrls) {
    if ([replaced.absoluteString isEqualToString:url.absoluteString]) {
      return true;
    }
  }
  return false;
}

@end
