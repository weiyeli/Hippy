//
//  HippyWaterfallView.m
//  HippyDemo
//
//  Created by Ricardo on 2021/1/19.
//  Copyright © 2021 tencent. All rights reserved.
//

#import "HippyWaterfallView.h"
#import "HippyCollectionViewWaterfallLayout.h"
#import "HippyHeaderRefresh.h"
#import "HippyFooterRefresh.h"

#define CELL_TAG 10089

typedef NS_ENUM(NSInteger, HippyScrollState) { ScrollStateStop, ScrollStateDraging, ScrollStateScrolling };

@interface HippyCollectionViewCell : UICollectionViewCell
@property (nonatomic, weak) HippyVirtualCell *node;
@property (nonatomic, assign) UIView *cellView;
@end

@implementation HippyCollectionViewCell

- (UIView *)cellView {
    return [self.contentView viewWithTag:CELL_TAG];
}

- (void)setCellView:(UIView *)cellView {
    UIView *selfCellView = [self cellView];
    if (selfCellView != cellView) {
        [selfCellView removeFromSuperview];
        cellView.tag = CELL_TAG;
        [self.contentView addSubview:cellView];
    }
}

@end

@interface HippyWaterfallView () <UICollectionViewDataSource, UICollectionViewDelegate, HippyCollectionViewDelegateWaterfallLayout, HippyInvalidating, HippyRefreshDelegate> {
    NSMutableArray *_scrollListeners;
    BOOL _isInitialListReady;
    HippyHeaderRefresh *_headerRefreshView;
    HippyFooterRefresh *_footerRefreshView;
}

@property (nonatomic, strong) HippyCollectionViewWaterfallLayout *layout;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, weak) HippyBridge *bridge;

@property (nonatomic, assign) NSInteger initialListSize;
@property (nonatomic, copy) HippyDirectEventBlock initialListReady;
@property (nonatomic, copy) HippyDirectEventBlock onEndReached;
@property (nonatomic, copy) HippyDirectEventBlock onFooterAppeared;
@property (nonatomic, copy) HippyDirectEventBlock onRefresh;
@property (nonatomic, copy) HippyDirectEventBlock onExposureReport;

@property (nonatomic, weak) HippyRootView *rootView;
@property (nonatomic, strong) UIView *loadingView;

@end

@implementation HippyWaterfallView {
    NSArray *_backgroundColors;
    double _lastOnScrollEventTimeInterval;
}

@synthesize node = _node;
@synthesize contentSize;

- (instancetype)initWithBridge:(HippyBridge *)bridge {
    if (self = [super initWithFrame:CGRectZero]) {
        self.backgroundColor = [UIColor clearColor];
        self.bridge = bridge;
        _scrollListeners = [NSMutableArray array];
        _scrollEventThrottle = 100.f;

        [self initCollectionView];

        if (@available(iOS 11.0, *)) {
            self.collectionView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        }
    }
    return self;
}

- (void)initCollectionView {
    if (_layout == nil) {
        _layout = [[HippyCollectionViewWaterfallLayout alloc] init];
    }

    if (_collectionView == nil) {
        _collectionView = [[UICollectionView alloc] initWithFrame:self.bounds collectionViewLayout:_layout];
        _collectionView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        _collectionView.dataSource = self;
        _collectionView.delegate = self;
        _collectionView.alwaysBounceVertical = YES;
        _collectionView.backgroundColor = [UIColor whiteColor];
        [_collectionView registerClass:[HippyCollectionViewCell class] forCellWithReuseIdentifier:@"Collection"];
        [_collectionView registerClass:[HippyCollectionViewCell class] forCellWithReuseIdentifier:@"BannerView"];

        [self addSubview:_collectionView];
    }
}

- (void)setScrollEventThrottle:(CFTimeInterval)scrollEventThrottle {
    _scrollEventThrottle = scrollEventThrottle;
}

- (void)removeHippySubview:(UIView *)subview {
}

- (void)hippySetFrame:(CGRect)frame {
    [super hippySetFrame:frame];
    _collectionView.frame = self.bounds;
}

- (NSArray<HippyVirtualNode *> *)nodesWithOnlyCell {
    NSMutableArray<HippyVirtualNode *> *subNodes = self.node.subNodes;
    NSUInteger first = 0;
    NSUInteger last = [subNodes count] - 1;
    if ([subNodes count] <= 0) {
        return subNodes;
    }
    if (_containBannerView) {
        first += 1;
    }
    if (_containPullHeader) {
        first += 1;
    }
    if (_containPullFooter) {
        last -= 1;
    }
    return [subNodes subarrayWithRange:NSMakeRange(first, last)];
}

- (__kindof HippyVirtualNode *)nodesWithBannerView {
    NSMutableArray<HippyVirtualNode *> *subNodes = self.node.subNodes;
    if ([subNodes count] > 0 && _containBannerView) {
        return subNodes[0];
    }
    return nil;
}

- (void)setBackgroundColors:(NSArray<UIColor *> *)backgroundColors {
    _backgroundColors = backgroundColors;
    _collectionView.backgroundColor = backgroundColors[0];
}

- (void)invalidate {
    [_scrollListeners removeAllObjects];
}

- (void)addScrollListener:(NSObject<UIScrollViewDelegate> *)scrollListener {
    [_scrollListeners addObject:scrollListener];
}

- (void)removeScrollListener:(NSObject<UIScrollViewDelegate> *)scrollListener {
    [_scrollListeners removeObject:scrollListener];
}

- (UIScrollView *)realScrollView {
    return _collectionView;
}

- (CGSize)contentSize {
    return _collectionView.contentSize;
}

- (NSArray *)scrollListeners {
    return _scrollListeners;
}

- (void)zoomToRect:(CGRect)rect animated:(BOOL)animated {
}

#pragma mark Setter

- (void)setContentInset:(UIEdgeInsets)contentInset {
    _contentInset = contentInset;

    _layout.sectionInset = _contentInset;
}

- (void)setNumberOfColumns:(NSInteger)numberOfColumns {
    _numberOfColumns = numberOfColumns;
    _layout.columnCount = _numberOfColumns;
}

- (void)setColumnSpacing:(CGFloat)columnSpacing {
    _columnSpacing = columnSpacing;
    _layout.minimumColumnSpacing = _columnSpacing;
}

- (void)setInterItemSpacing:(CGFloat)interItemSpacing {
    _interItemSpacing = interItemSpacing;
    _layout.minimumInteritemSpacing = _interItemSpacing;
}

- (BOOL)flush {
    NSInteger numberOfRows = [self.node.props[@"numberOfRows"] integerValue];
    if (self.node.subNodes.count != 0 && self.node.subNodes.count == numberOfRows) {
        [self.collectionView reloadData];
        if (!_isInitialListReady) {
            _isInitialListReady = YES;
            self.initialListReady(@{});
        }
        return YES;
    }
    return NO;
}

- (void)insertHippySubview:(UIView *)subview atIndex:(NSInteger)atIndex
{
    if ([subview isKindOfClass:[HippyHeaderRefresh class]]) {
        if (_headerRefreshView) {
            [_headerRefreshView removeFromSuperview];
        }
        _headerRefreshView = (HippyHeaderRefresh *)subview;
        [_headerRefreshView setScrollView:self.collectionView];
        _headerRefreshView.delegate = self;
        _headerRefreshView.frame = [self.node.subNodes[atIndex] frame];
    } else if ([subview isKindOfClass:[HippyFooterRefresh class]]) {
        if (_footerRefreshView) {
            [_footerRefreshView removeFromSuperview];
        }
        _footerRefreshView = (HippyFooterRefresh *)subview;
        [_footerRefreshView setScrollView:self.collectionView];
        _footerRefreshView.delegate = self;
        _footerRefreshView.frame = [self.node.subNodes[atIndex] frame];
    }
}

#pragma mark - UICollectionViewDataSource
- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    if (_containBannerView) {
        return 2;
    }
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if (_containBannerView) {
        if (0 == section) {
            return 1;
        }
    }
    NSInteger count = [[self nodesWithOnlyCell] count];
    return count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (_containBannerView && 0 == [indexPath section]) {
        return [self collectionView:collectionView bannerViewForItemAtIndexPath:indexPath];
    }
    return [self collectionView:collectionView itemViewForItemAtIndexPath:indexPath];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView bannerViewForItemAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"BannerView";
    HippyVirtualCell *newNode = [self nodesWithBannerView];
    HippyCollectionViewCell *cell = (HippyCollectionViewCell *)[collectionView dequeueReusableCellWithReuseIdentifier:identifier forIndexPath:indexPath];
    if (nil == cell.cellView) {
        UIView *cellView = [_bridge.uiManager updateNode:cell.node withNode:newNode];
        if (cellView == nil) {
            cell.cellView = [_bridge.uiManager createViewFromNode:newNode];
        } else {
            cell.cellView = cellView;
        }
    }
    return cell;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView itemViewForItemAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"Collection";
    HippyVirtualCell *newNode = (HippyVirtualCell *)[self nodesWithOnlyCell][indexPath.item];
    NSString *itemIdentifier = newNode.itemViewType;

    HippyCollectionViewCell *cell = (HippyCollectionViewCell *)[collectionView dequeueReusableCellWithReuseIdentifier:identifier forIndexPath:indexPath];
    while (cell && cell.node && !([[(HippyVirtualCell *)cell.node itemViewType] isEqualToString:itemIdentifier])) {
        [cell removeFromSuperview];
        cell = (HippyCollectionViewCell *)[collectionView dequeueReusableCellWithReuseIdentifier:identifier forIndexPath:indexPath];
        if (cell == nil) {
            HippyLogInfo(@"cannot find right cell:%@", @(indexPath.row));
        }
    }
    if (cell.node && cell.node.cell != cell) {
        [cell.cellView removeFromSuperview];
        cell.cellView = nil;
        cell.node = nil;
    }

    if (cell == nil) {
        cell = (HippyCollectionViewCell *)[collectionView dequeueReusableCellWithReuseIdentifier:identifier forIndexPath:indexPath];
        cell.cellView = [_bridge.uiManager createViewFromNode:newNode];
    } else {
        if (cell.node && cell.node.cell) {
            UIView *cellView = [_bridge.uiManager updateNode:cell.node withNode:newNode];
            if (cellView == nil) {
                cell.cellView = [_bridge.uiManager createViewFromNode:newNode];
            } else {
                cell.cellView = cellView;
            }
        } else {
            cell.cellView = [_bridge.uiManager createViewFromNode:newNode];
        }
    }
    cell.node.cell = nil;
    newNode.cell = cell;
    cell.node = newNode;
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView
       willDisplayCell:(UICollectionViewCell *)cell
    forItemAtIndexPath:(NSIndexPath *)indexPath NS_AVAILABLE_IOS(8_0) {
    if (0 == [indexPath section] && _containBannerView) {
        return;
    }
    NSInteger count = [self nodesWithOnlyCell].count;
    NSInteger leftCnt = count - indexPath.item - 1;
    if (leftCnt == _preloadItemNumber) {
        [self startLoadMoreData];
    }

    if (indexPath.item == count - 1) {
        [self startLoadMoreData];
        if (self.onFooterAppeared) { // 延迟0.5s去做这个通知
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                self.onFooterAppeared(@ {});
            });
        }
    }
}

#pragma mark - HippyCollectionViewDelegateWaterfallLayout
- (CGSize)collectionView:(UICollectionView *)collectionView
                    layout:(UICollectionViewLayout *)collectionViewLayout
    sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger section = [indexPath section];
    NSInteger row = [indexPath item];
    if (_containBannerView) {
        if (0 == section) {
            HippyVirtualNode *node = [self nodesWithBannerView];
            return node.frame.size;
        } else {
            NSArray<HippyVirtualNode *> *subNodes = [self nodesWithOnlyCell];
            if ([subNodes count] > row) {
                HippyVirtualNode *node = subNodes[row];
                return node.frame.size;
            }
        }
    } else {
        NSArray<HippyVirtualNode *> *subNodes = [self nodesWithOnlyCell];
        if ([subNodes count] > row) {
            HippyVirtualNode *node = subNodes[row];
            return node.frame.size;
        }
    }
    return CGSizeZero;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView
                     layout:(UICollectionViewLayout *)collectionViewLayout
      columnCountForSection:(NSInteger)section {
    if (_containBannerView && 0 == section) {
        return 1;
    }
    return _numberOfColumns;
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView
                        layout:(UICollectionViewLayout *)collectionViewLayout
        insetForSectionAtIndex:(NSInteger)section {
    if (0 == section && _containBannerView) {
        return UIEdgeInsetsZero;
    }
    return _contentInset;
}

- (void)startLoadMore {
    [self startLoadMoreData];
}

- (void)startLoadMoreData {
    [self loadMoreData];
}

- (void)loadMoreData {
    if (self.onEndReached) {
        self.onEndReached(@{});
    }
}

- (void)endReachedCompleted:(NSInteger)status text:(NSString *)text {
    
}

#pragma mark - UIScrollView Delegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (_onScroll) {
        double ti = CACurrentMediaTime();
        double timeDiff = (ti - _lastOnScrollEventTimeInterval) * 1000.f;
        if (timeDiff > _scrollEventThrottle) {
            NSDictionary *eventData = [self scrollEventDataWithState:ScrollStateScrolling];
            _lastOnScrollEventTimeInterval = ti;
            _onScroll(eventData);
        }
    }
}

- (NSDictionary *)scrollEventDataWithState:(HippyScrollState)state {
    NSArray<NSIndexPath *> *visibleItems = [self indexPathsForVisibleItems];
    if ([visibleItems count] > 0) {
        CGPoint offset = self.collectionView.contentOffset;
        CGFloat startEdgePos = offset.y;
        CGFloat endEdgePos = offset.y + CGRectGetHeight(self.collectionView.frame);
        NSInteger firstVisibleRowIndex = [[visibleItems firstObject] row];
        NSInteger lastVisibleRowIndex = [[visibleItems lastObject] row];

        //此时是banner，最后一个显示的坐标要加上前面的banner
        if (_containBannerView) {
            if ([visibleItems firstObject].section == 0) {    //第1个是banner
                if ([visibleItems lastObject].section != 0) { //最后一个在第二个section中
                    lastVisibleRowIndex = lastVisibleRowIndex + 1;
                }
            } else { // banner已经不可见了，展示的都是第二个section的内容
                firstVisibleRowIndex = firstVisibleRowIndex + 1;
                lastVisibleRowIndex = lastVisibleRowIndex + 1;
            }
        }

        NSMutableArray *visibleRowsFrames = [NSMutableArray arrayWithCapacity:[visibleItems count]];
        for (NSIndexPath *indexPath in visibleItems) {
            UICollectionViewCell *node = [self.collectionView cellForItemAtIndexPath:indexPath];
            [visibleRowsFrames addObject:@{
                @"x" : @(node.frame.origin.x),
                @"y" : @(node.frame.origin.y),
                @"width" : @(CGRectGetWidth(node.frame)),
                @"height" : @(CGRectGetHeight(node.frame))
            }];
        }
        NSDictionary *dic = @{
            @"startEdgePos" : @(startEdgePos),
            @"endEdgePos" : @(endEdgePos),
            @"firstVisibleRowIndex" : @(firstVisibleRowIndex),
            @"lastVisibleRowIndex" : @(lastVisibleRowIndex),
            @"scrollState" : @(state),
            @"visibleRowFrames" : visibleRowsFrames
        };
        return dic;
    }
    return [NSDictionary dictionary];
}

- (NSArray<NSIndexPath *> *)indexPathsForVisibleItems {
    NSArray<NSIndexPath *> *visibleItems = [self.collectionView indexPathsForVisibleItems];
    NSArray<NSIndexPath *> *sortedItems = [visibleItems sortedArrayUsingComparator:^NSComparisonResult(id _Nonnull obj1, id _Nonnull obj2) {
        NSIndexPath *ip1 = (NSIndexPath *)obj1;
        NSIndexPath *ip2 = (NSIndexPath *)obj2;
        return [ip1 compare:ip2];
    }];
    return sortedItems;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) {
        if (self.onExposureReport) {
            HippyScrollState state = scrollView.decelerating ? ScrollStateScrolling : ScrollStateStop;
            NSDictionary *exposureInfo = [self scrollEventDataWithState:state];
            self.onExposureReport(exposureInfo);
        }
    }
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView NS_AVAILABLE_IOS(3_2) {
    
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView;
{
    [self cancelTouch];
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
                     withVelocity:(CGPoint)velocity
              targetContentOffset:(inout CGPoint *)targetContentOffset NS_AVAILABLE_IOS(5_0);
{
    if (velocity.y > 0) {
        if (self.onExposureReport) {
            NSDictionary *exposureInfo = [self scrollEventDataWithState:ScrollStateScrolling];
            self.onExposureReport(exposureInfo);
        }
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView;
{
    if (self.onExposureReport) {
        NSDictionary *exposureInfo = [self scrollEventDataWithState:ScrollStateStop];
        self.onExposureReport(exposureInfo);
    }
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
}

- (nullable UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView;
{ return nil; }

- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(nullable UIView *)view NS_AVAILABLE_IOS(3_2) {
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(nullable UIView *)view atScale:(CGFloat)scale {
}

- (BOOL)scrollViewShouldScrollToTop:(UIScrollView *)scrollViewxt {
    return YES;
}

- (void)scrollViewDidScrollToTop:(UIScrollView *)scrollView {
}

#pragma mark -
#pragma mark JS CALL Native
- (void)refreshCompleted:(NSInteger)status text:(NSString *)text {
}

- (void)startRefreshFromJS {
}

- (void)startRefreshFromJSWithType:(NSUInteger)type {
    if (type == 1) {
        [self startRefreshFromJS];
    }
}

- (void)callExposureReport {
    BOOL isDragging = self.collectionView.isDragging;
    BOOL isDecelerating = self.collectionView.isDecelerating;
    BOOL isScrolling = isDragging || isDecelerating;
    HippyScrollState state = isScrolling ? ScrollStateScrolling : ScrollStateStop;
    NSDictionary *result = [self scrollEventDataWithState:state];
    if (self.onExposureReport) {
        self.onExposureReport(result);
    }
}

- (void)scrollToOffset:(CGPoint)point animated:(BOOL)animated {
    [self.collectionView setContentOffset:point animated:animated];
}

- (void)scrollToIndex:(NSInteger)index animated:(BOOL)animated {
}

#pragma mark touch conflict
- (HippyRootView *)rootView {
    if (_rootView) {
        return _rootView;
    }

    UIView *view = [self superview];

    while (view && ![view isKindOfClass:[HippyRootView class]]) {
        view = [view superview];
    }

    if ([view isKindOfClass:[HippyRootView class]]) {
        _rootView = (HippyRootView *)view;
        return _rootView;
    } else
        return nil;
}

- (void)cancelTouch {
    HippyRootView *view = [self rootView];
    if (view) {
        [view cancelTouches];
    }
}

- (void)didMoveToSuperview {
    _rootView = nil;
}

@end
