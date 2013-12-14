//
//  GTWAOFRawQuads.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/9/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

/**
 4  cookie          [RQDS]
 4  padding
 8  timestamp       (seconds since epoch)
 8  prev_page_id
 8  count
 *  DATA
 */
#import "GTWAOFRawQuads.h"
#import "GTWAOFUpdateContext.h"

#define TS_OFFSET       8
#define PREV_OFFSET     16
#define COUNT_OFFSET    24
#define DATA_OFFSET     32

@implementation GTWAOFRawQuads

+ (GTWAOFRawQuads*) quadsWithQuads:(NSArray *)quads aof:(id<GTWAOF>)_aof {
    NSMutableArray* q   = [[quads sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        int r   = memcmp([obj1 bytes], [obj2 bytes], 32);
        if (r < 0) {
            return NSOrderedAscending;
        } else if (r > 0) {
            return NSOrderedDescending;
        } else {
            return NSOrderedSame;
        }
    }] mutableCopy];
    __block GTWAOFPage* page;
    BOOL ok = [_aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
        int64_t prev  = -1;
        if ([q count]) {
            while ([q count]) {
//                NSLog(@"%llu quads remaining", (unsigned long long)[q count]);
                NSData* data    = newQuadsData([_aof pageSize], q, prev, NO);
                if(!data)
                    return NO;
                page    = [ctx createPageWithData:data];
                prev    = page.pageID;
            }
        } else {
            NSData* empty   = emptyQuadsData([_aof pageSize], prev, NO);
            page            = [ctx createPageWithData:empty];
        }
        return YES;
    }];
    if (!ok)
        return nil;
//    NSLog(@"new quads head: %@", page);
    return [[GTWAOFRawQuads alloc] initWithPage:page fromAOF:_aof];
}

- (GTWAOFRawQuads*) quadsByAddingQuads:(NSArray*) quads {
    NSMutableArray* q   = [[quads sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        int r   = memcmp([obj1 bytes], [obj2 bytes], 32);
        if (r < 0) {
            return NSOrderedAscending;
        } else if (r > 0) {
            return NSOrderedDescending;
        } else {
            return NSOrderedSame;
        }
    }] mutableCopy];
    __block GTWAOFPage* page;
    BOOL ok = [_aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
        int64_t prev  = self.pageID;
        if ([q count]) {
            while ([q count]) {
//                NSLog(@"%llu quads remaining", (unsigned long long)[q count]);
                NSData* data    = newQuadsData([_aof pageSize], q, prev, self.verbose);
                if(!data)
                    return NO;
                page    = [ctx createPageWithData:data];
                prev    = page.pageID;
            }
        } else {
            NSData* empty   = emptyQuadsData([_aof pageSize], prev, self.verbose);
            page            = [ctx createPageWithData:empty];
        }
        return YES;
    }];
    if (!ok)
        return nil;
    //    NSLog(@"new quads head: %@", page);
    return [[GTWAOFRawQuads alloc] initWithPage:page fromAOF:_aof];
}

- (GTWAOFRawQuads*) initFindingQuadsInAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof    = aof;
        _head   = nil;
        NSInteger pageID;
        NSInteger pageCount = [aof pageCount];
        for (pageID = pageCount-1; pageID >= 0; pageID--) {
            //            NSLog(@"Checking block %lu for dictionary head", pageID);
            GTWAOFPage* p   = [aof readPage:pageID];
            NSData* data    = p.data;
            char cookie[5] = { 0,0,0,0,0 };
            [data getBytes:cookie length:4];
            if (!strncmp(cookie, RAW_QUADS_COOKIE, 4)) {
                _head   = p;
                break;
            }
        }
        
        if (!_head) {
            return [GTWAOFRawQuads quadsWithQuads:@[] aof:aof];
        }
    }
    return self;
}

- (GTWAOFRawQuads*) initWithPageID:(NSInteger)pageID fromAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof    = aof;
        _head   = [aof readPage:pageID];
    }
    return self;
}

- (GTWAOFRawQuads*) initWithPage:(GTWAOFPage*)page fromAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof    = aof;
        _head   = page;
    }
    return self;
}

- (NSInteger) pageID {
    return _head.pageID;
}

- (NSInteger) previousPageID {
    GTWAOFPage* p   = _head;
    NSData* data    = p.data;
    uint64_t big_prev = 0;
    [data getBytes:&big_prev range:NSMakeRange(PREV_OFFSET, 8)];
    unsigned long long prev = NSSwapBigLongLongToHost((unsigned long long) big_prev);
    return (NSInteger) prev;
}

- (GTWAOFPage*) head {
    return _head;
}

- (NSDate*) lastModified {
    GTWAOFPage* p   = _head;
    NSData* data    = p.data;
    uint64_t big_ts = 0;
    [data getBytes:&big_ts range:NSMakeRange(TS_OFFSET, 8)];
    unsigned long long ts = NSSwapBigLongLongToHost((unsigned long long) big_ts);
    return [NSDate dateWithTimeIntervalSince1970:(double)ts];
}

- (NSUInteger) count {
    GTWAOFPage* p       = _head;
    NSData* data        = p.data;
    uint64_t big_count  = 0;
    [data getBytes:&big_count range:NSMakeRange(COUNT_OFFSET, 8)];
    unsigned long long count = NSSwapBigLongLongToHost((unsigned long long) big_count);
    return (NSUInteger) count;
}

- (id) objectAtIndex: (NSUInteger) index {
    GTWAOFPage* p   = _head;
    NSData* data    = p.data;
    char* buf       = malloc(32);
    unsigned long offset    = DATA_OFFSET + (index*32);
    [data getBytes:buf range:NSMakeRange(offset, 32)];
    return [NSData dataWithBytesNoCopy:buf length:32];
}

+ (void)enumerateObjectsForPage:(NSInteger) pageID fromAOF:(id<GTWAOF>)aof usingBlock:(void (^)(id key, NSUInteger idx, BOOL *stop))block followTail:(BOOL)follow {
    @autoreleasepool {
        while (pageID >= 0) {
            GTWAOFRawQuads* q  = [[GTWAOFRawQuads alloc] initWithPageID:pageID fromAOF:aof];
//            NSLog(@"Quads Page: %lu", q.pageID);
//            NSLog(@"Quads Page Last-Modified: %@", [q lastModified]);
            GTWAOFPage* p   = q.head;
            NSData* data    = p.data;
            int64_t big_prev_page_id    = -1;
            [data getBytes:&big_prev_page_id range:NSMakeRange(PREV_OFFSET, 8)];
            long long prev_page_id = NSSwapBigLongLongToHost(big_prev_page_id);
//            NSLog(@"Quads Previous Page: %"PRId64, prev_page_id);
            
            NSUInteger count    = [q count];
            NSUInteger i;
            BOOL stop   = NO;
            for (i = 0; i < count; i++) {
                NSData* quad   = [q objectAtIndex:i];
                block(quad, i, &stop);
                if (stop)
                    break;
            }
            
            pageID  = prev_page_id;
            if (!follow)
                break;
        }
    }
}

- (void)enumerateObjectsUsingBlock:(void (^)(id obj, NSUInteger idx, BOOL *stop))block {
    [GTWAOFRawQuads enumerateObjectsForPage:self.pageID fromAOF:_aof usingBlock:block followTail:YES];
}

NSMutableData* emptyQuadsData( NSUInteger pageSize, int64_t prevPageID, BOOL verbose ) {
    uint64_t ts     = (uint64_t) [[NSDate date] timeIntervalSince1970];
    int64_t prev    = (int64_t) prevPageID;
    if (verbose) {
        NSLog(@"creating quads page data with previous page ID: %lld (%lld)", prevPageID, prev);
    }
    uint64_t bigts  = NSSwapHostLongLongToBig(ts);
    int64_t bigprev = NSSwapHostLongLongToBig(prev);
    
    int64_t bigcount    = 0;
    
    NSMutableData* data = [NSMutableData dataWithLength:pageSize];
    [data replaceBytesInRange:NSMakeRange(0, 4) withBytes:RAW_QUADS_COOKIE];
    [data replaceBytesInRange:NSMakeRange(TS_OFFSET, 8) withBytes:&bigts];
    [data replaceBytesInRange:NSMakeRange(PREV_OFFSET, 8) withBytes:&bigprev];
    [data replaceBytesInRange:NSMakeRange(COUNT_OFFSET, 8) withBytes:&bigcount];
    return data;
}

NSData* newQuadsData( NSUInteger pageSize, NSMutableArray* quads, int64_t prevPageID, BOOL verbose ) {
    int64_t max     = (pageSize / 32) - 1;
    int64_t qcount  = [quads count];
    int64_t count   = (max < qcount) ? max : qcount;
    int64_t bigcount    = NSSwapHostLongLongToBig(count);
    
    NSMutableData* data = emptyQuadsData(pageSize, prevPageID, verbose);
    [data replaceBytesInRange:NSMakeRange(COUNT_OFFSET, 8) withBytes:&bigcount];
    __block int offset  = DATA_OFFSET;
    NSUInteger i;
    for (i = 0; i < count; i++) {
        NSData* q   = quads[i];
        if (verbose) {
            NSLog(@"handling quad: %@", q);
        }
        if (![q isKindOfClass:[NSData class]]) {
            NSLog(@"Attempt to add quad that is not a NSData object (%@)", [q class]);
            return nil;
        }
        if ([q length] != 32) {
            NSLog(@"Attempt to add quad data that has unexpected length (%ld)", [q length]);
            return nil;
        }
        
        [data replaceBytesInRange:NSMakeRange(offset, 32) withBytes:[q bytes]];
        offset  += 32;
    }
    [quads removeObjectsInRange:NSMakeRange(0,count)];
    if ([data length] != pageSize) {
        NSLog(@"page has bad size for quads");
        return nil;
    }
    return data;
}

@end