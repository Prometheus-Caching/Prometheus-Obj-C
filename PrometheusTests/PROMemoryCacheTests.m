//
//  PROMemoryCacheTests.m
//  Prometheus
//
//  Copyright (c) 2015 Comyar Zaheri. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.
//


#pragma mark - Imports

@import XCTest;

#import "Prometheus.h"
#import "PrometheusInternal.h"


#pragma mark - Constants and Functions

static NSTimeInterval DefaultAsyncTestTimeout = 10.0;
static inline dispatch_time_t timeout(NSTimeInterval seconds) {
    return dispatch_time(DISPATCH_TIME_NOW, (int64_t) seconds * NSEC_PER_SEC);
}


#pragma mark - PROMemoryCache Private Category Interface

@interface PROMemoryCache (Private)

@property (readonly) NSMutableDictionary    *reads;
@property (readonly) NSMutableDictionary    *cache;
@property (assign) NSUInteger currentMemoryUsage;

@end


#pragma mark - PROMemoryCacheTests Interface

@interface PROMemoryCacheTests : XCTestCase

@end


#pragma mark - PROMemoryCacheTests Implementation

@implementation PROMemoryCacheTests

- (void)testDesignatedInitializer
{
    PROMemoryCache *cache = [[PROMemoryCache alloc]initWithMemoryCapacity:1000];
    XCTAssertEqual(1000, cache.memoryCapacity);
    XCTAssertEqual(0, cache.currentMemoryUsage);
#if TARGET_OS_IPHONE
    XCTAssertEqual(YES, cache.removesAllCachedDataOnMemoryWarning);
    XCTAssertEqual(YES, cache.removesAllCachedDataOnEnteringBackground);
#endif
}

#pragma mark Asynchronous Test

- (void)testCachedDataForKeyCompletion
{
    PROMemoryCache *cache = [[PROMemoryCache alloc]initWithMemoryCapacity:1000];
    PROCachedData *expected = [self randomCachedDataWithLifetime:10];
    cache.cache[@"test"] = expected;
    
    __block PROCachedData *actual = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [cache cachedDataForKey:@"test" completion:^(id<PROCaching> cache, NSString *key, PROCachedData *data) {
        actual = data;
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, timeout(DefaultAsyncTestTimeout));
    
    XCTAssertEqualObjects(expected, actual);
    XCTAssertNotNil(cache.reads[@"test"]);
}

- (void)testStoreCachedDataForKeyCompletion
{
    PROMemoryCache *cache = [[PROMemoryCache alloc]initWithMemoryCapacity:1000];
    PROCachedData *expectedData = [self randomCachedDataWithLifetime:10];
    NSString *expectedKey = @"test";
    
    __block NSString *actualKey = nil;
    __block PROCachedData *actualData = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [cache storeCachedData:expectedData forKey:@"test" completion:^(id<PROCaching> cache, NSString *key, PROCachedData *data) {
        actualKey = key;
        actualData = data;
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, timeout(DefaultAsyncTestTimeout));
    
    XCTAssertNotNil(cache.reads[expectedKey]);
    XCTAssertEqualObjects(expectedKey, actualKey);
    XCTAssertEqualObjects(expectedData, actualData);
    XCTAssertEqualObjects(expectedData, cache.cache[expectedKey]);
}

- (void)testStoreCachedDataForKeyCompletionStoragePolicy
{
    PROMemoryCache *cache = [[PROMemoryCache alloc]initWithMemoryCapacity:1000];
    PROCachedData *expectedData = [self randomCachedDataWithLifetime:10];
    expectedData.storagePolicy = PROCacheStoragePolicyNotAllowed;
    NSString *expectedKey = @"test";
    
    __block NSString *actualKey = nil;
    __block PROCachedData *actualData = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [cache storeCachedData:expectedData forKey:@"test" completion:^(id<PROCaching> cache, NSString *key, PROCachedData *data) {
        actualKey = key;
        actualData = data;
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, timeout(DefaultAsyncTestTimeout));
    
    XCTAssertNil(actualData);
    XCTAssertNil(cache.cache[expectedKey]);
    XCTAssertNil(cache.reads[expectedKey]);
    XCTAssertEqualObjects(expectedKey, actualKey);
    XCTAssertEqual(0, cache.currentMemoryUsage);
}

- (void)testRemoveAllCachedDataWithCompletion
{
    PROMemoryCache *cache = [[PROMemoryCache alloc]initWithMemoryCapacity:256000];
    for (int i = 0; i < 1000; ++i) {
        NSString *key = [NSString stringWithFormat:@"test%d", i];
        PROCachedData *data = [self randomCachedDataWithLifetime:60];
        cache.cache[key] = data;
        cache.reads[key] = [NSDate date];
    }
    cache.currentMemoryUsage = 256000;
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [cache removeAllCachedDataWithCompletion:^(id<PROCaching> cache, BOOL success) {
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, timeout(DefaultAsyncTestTimeout));
    
    XCTAssertEqual(0, cache.currentMemoryUsage);
    XCTAssertEqual(0, [cache.reads count]);
    XCTAssertEqual(0, [cache.cache count]);
}

- (void)testRemoveCachedDataForKeyCompletion
{
    PROMemoryCache *cache = [[PROMemoryCache alloc]initWithMemoryCapacity:1000];
    PROCachedData *data = [self randomCachedDataWithLifetime:10];
    cache.cache[@"test"] = data;
    cache.reads[@"test"] = [NSDate date];
    cache.currentMemoryUsage = data.size;
    
    __block NSString *actualKey = nil;
    __block PROCachedData *actualData = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [cache removeCachedDataForKey:@"test" completion:^(id<PROCaching> cache, NSString *key, PROCachedData *data) {
        actualKey = key;
        actualData = data;
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, timeout(DefaultAsyncTestTimeout));
    
    XCTAssertNil(actualData);
    XCTAssertEqualObjects(@"test", actualKey);
    XCTAssertEqual(0, cache.currentMemoryUsage);
}

#pragma mark Synchronous Tests

- (void)testCachedDataForKey
{
    PROMemoryCache *cache = [[PROMemoryCache alloc]initWithMemoryCapacity:1000];
    PROCachedData *expected = [self randomCachedDataWithLifetime:10];
    cache.cache[@"test"] = expected;
    
    PROCachedData *actual = [cache cachedDataForKey:@"test"];
    
    XCTAssertEqualObjects(expected, actual);
    XCTAssertNotNil(cache.reads[@"test"]);
}

- (void)testStoreCachedDataForKey
{
    PROMemoryCache *cache = [[PROMemoryCache alloc]initWithMemoryCapacity:1000];
    PROCachedData *expected = [self randomCachedDataWithLifetime:10];
    
    [cache storeCachedData:expected forKey:@"test"];
    
    XCTAssertEqual(expected.size, cache.currentMemoryUsage);
    XCTAssertEqualObjects(expected, cache.cache[@"test"]);
    XCTAssertNotNil(cache.reads[@"test"]);
}

- (void)testStoreCachedDataForKeyStoragePolicy
{
    PROMemoryCache *cache = [[PROMemoryCache alloc]initWithMemoryCapacity:1000];
    PROCachedData *expected = [self randomCachedDataWithLifetime:10];
    expected.storagePolicy = PROCacheStoragePolicyNotAllowed;
    
    [cache storeCachedData:expected forKey:@"test"];
    
    PROCachedData *actual = [cache.cache objectForKey:@"test"];
    XCTAssertEqual(0, cache.currentMemoryUsage);
    XCTAssertNil(cache.reads[@"test"]);
    XCTAssertNil(actual);
}

- (void)testRemoveAllCachedData
{
    PROMemoryCache *cache = [[PROMemoryCache alloc]initWithMemoryCapacity:256000];
    for (int i = 0; i < 1000; ++i) {
        PROCachedData *data = [self randomCachedDataWithLifetime:60];
        NSString *key = [NSString stringWithFormat:@"test%d", i];
        cache.reads[key] = [NSDate date];
        cache.cache[key] = data;
    }
    
    [cache removeAllCachedData];
    
    XCTAssertEqual(0, cache.currentMemoryUsage);
    XCTAssertEqual(0, [cache.reads count]);
    XCTAssertEqual(0, [cache.cache count]);
}

- (void)testRemoveCachedDataForKey
{
    PROMemoryCache *cache = [[PROMemoryCache alloc]initWithMemoryCapacity:1000];
    PROCachedData *data = [self randomCachedDataWithLifetime:10];
    cache.currentMemoryUsage = data.size;
    cache.reads[@"test"] = [NSDate date];
    cache.cache[@"test"] = data;
    
    [cache removeCachedDataForKey:@"test"];
    
    XCTAssertNil(cache.cache[@"test"]);
    XCTAssertNil(cache.reads[@"test"]);
    XCTAssertEqual(0, cache.currentMemoryUsage);
}

#pragma mark Garbage Collect Tests

- (void)testGarbageCollectsExpired
{
    PROMemoryCache *cache = [[PROMemoryCache alloc]initWithMemoryCapacity:1000];
    PROCachedData *data = [self randomCachedDataWithLifetime:1];
    [cache storeCachedData:data forKey:@"test"];
    XCTAssertNotNil(cache.cache[@"test"]);
    while ([data.expiration timeIntervalSinceNow]) {} // spin and wait
    [cache garbageCollectWithDate:[NSDate date]];
    XCTAssertNil([cache cachedDataForKey:@"test"]);
}

- (void)testGarbageCollectsLRU
{
    PROMemoryCache *cache = [[PROMemoryCache alloc]initWithMemoryCapacity:1000];
    cache.cache[@"test1"] = [self randomCachedDataWithLifetime:10];
    cache.cache[@"test2"] = [self randomCachedDataWithLifetime:10];
    cache.reads[@"test1"] = [[NSDate date]dateByAddingTimeInterval:-100];
    cache.reads[@"test2"] = [NSDate date];
    cache.currentMemoryUsage = 1000;
    [cache garbageCollectWithDate:[NSDate date]];
    
    XCTAssertNil([cache cachedDataForKey:@"test1"]);
    XCTAssertNotNil([cache cachedDataForKey:@"test2"]);
}

#pragma mark Deadlock Tests

- (void)testForDeadlock
{
    PROMemoryCache *cache = [[PROMemoryCache alloc]initWithMemoryCapacity:2560000];
    PROCachedData *expected = [self randomCachedDataWithLifetime:10];
    
    [cache storeCachedData:expected forKey:@"test"];
    
    dispatch_queue_t queue = dispatch_queue_create("test.prometheus.memory", DISPATCH_QUEUE_CONCURRENT);
    
    int numFetches = 10000;
    __block NSUInteger completedFetches = 0;
    NSLock *lock = [NSLock new];
    dispatch_group_t group = dispatch_group_create();
    for (int i = 0; i < numFetches; ++i) {
        dispatch_group_async(group, queue, ^{
            [cache cachedDataForKey:@"test"];
            [cache storeCachedData:expected forKey:@"test"
                        completion:^(__weak id<PROCaching> cache, NSString *key, PROCachedData *data) {
                            [cache cachedDataForKey:@"test"];
            }];
            [cache storeCachedData:expected forKey:@"test"];
            [cache cachedDataForKey:@"test"
                         completion:^(__weak id<PROCaching> cache, NSString *key, PROCachedData *data) {
                             [cache storeCachedData:data forKey:key];
            }];
            [lock lock];
            completedFetches++;
            [lock unlock];
        });
    }
    
    dispatch_group_wait(group, timeout(DefaultAsyncTestTimeout));
    XCTAssertTrue(numFetches == completedFetches, @"didn't complete operations, possibly due to deadlock.");
}

#pragma mark Helper

- (PROCachedData *)cachedDataWithLifetime:(NSTimeInterval)lifetime length:(NSUInteger)length
{
    // this is pretty sketchy, only use for testing!
    NSMutableData *data = [NSMutableData dataWithBytes:malloc(length)
                                                length:length];
    return [PROCachedData cachedDataWithData:data lifetime:lifetime];
}

- (PROCachedData *)randomCachedDataWithLifetime:(NSTimeInterval)lifetime
{
    NSUInteger length = arc4random() % 256;
    return [self cachedDataWithLifetime:lifetime length:length];
}

@end
