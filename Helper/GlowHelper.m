// GlowHelper - companion dylib for Glow for Facebook.
// Adds a second entry point to Glow settings: long-press on the
// Facebook logo in the app's top bar. The original long-press-on-tab
// trigger inside Glow.dylib is left untouched.

#import <UIKit/UIKit.h>

static const NSTimeInterval kGHPressDuration = 3.0;
static const NSTimeInterval kGHScanInterval = 2.0;
static const CGFloat kGHZoneMaxX = 170.0;
static const CGFloat kGHZoneMinY = 40.0;
static const CGFloat kGHZoneMaxY = 115.0;
static const CGFloat kGHTouchSlop = 10.0;

static UIWindow *GHKeyWindow(void) {
    UIApplication *app = UIApplication.sharedApplication;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        if (scene.activationState == UISceneActivationStateUnattached) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) return w;
        }
    }
    return app.windows.firstObject;
}

@interface GHLogoLongPress : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *logoView;
@property (nonatomic, strong) UILongPressGestureRecognizer *recognizer;
@property (nonatomic, strong) NSTimer *timer;
+ (instancetype)shared;
- (void)tick;
@end

@implementation GHLogoLongPress

+ (instancetype)shared {
    static GHLogoLongPress *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [GHLogoLongPress new]; });
    return s;
}

- (void)tick {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self attach];
        if (!self.timer) {
            self.timer = [NSTimer scheduledTimerWithTimeInterval:kGHScanInterval
                                                         repeats:YES
                                                           block:^(NSTimer *t) { [self attach]; }];
            self.timer.tolerance = 1.0;
        }
    });
}

- (BOOL)isInTopBand:(CGRect)f {
    return f.origin.y < 160.0 && f.origin.y + f.size.height > 30.0;
}

- (UIView *)findLogoViewIn:(UIView *)root depth:(int)depth {
    if (depth > 14) return nil;
    UIWindow *win = root.window;
    for (UIView *v in root.subviews) {
        CGRect f = [v convertRect:v.bounds toView:win];
        if (![self isInTopBand:f]) continue;
        if (CGRectGetMidX(f) < kGHZoneMaxX) {
            NSString *al = v.accessibilityLabel ?: @"";
            NSString *ai = v.accessibilityIdentifier ?: @"";
            NSString *cn = NSStringFromClass(v.class);
            if (f.size.width > 8.0 && f.size.height > 8.0 &&
                ([al.lowercaseString containsString:@"facebook"] ||
                 [ai.lowercaseString containsString:@"facebook"] ||
                 [cn containsString:@"Logo"])) {
                return v;
            }
        }
        UIView *r = [self findLogoViewIn:v depth:depth + 1];
        if (r) return r;
    }
    return nil;
}

- (UIView *)hitTestLogo:(UIWindow *)win {
    static const CGFloat pts[][2] = {
        {24, 58}, {45, 60}, {70, 60}, {100, 60}, {30, 70}, {15, 54}
    };
    for (NSUInteger i = 0; i < sizeof(pts) / sizeof(pts[0]); i++) {
        UIView *v = [win hitTest:CGPointMake(pts[i][0], pts[i][1]) withEvent:nil];
        if (!v) continue;
        CGRect f = [v convertRect:v.bounds toView:win];
        if ([self isInTopBand:f] &&
            f.size.width > 8.0 && f.size.width < 220.0 &&
            f.size.height > 8.0 && f.size.height < 64.0) {
            return v;
        }
    }
    return nil;
}

- (UIView *)interactiveAncestorOf:(UIView *)v {
    for (UIView *a = v; a; a = a.superview) {
        if (a.userInteractionEnabled && !a.hidden && a.alpha > 0.01) return a;
    }
    return v;
}

- (void)attach {
    UIWindow *win = GHKeyWindow();
    if (!win) return;

    UIView *logo = [self findLogoViewIn:win depth:0] ?: [self hitTestLogo:win];
    self.logoView = logo;
    UIView *target = logo ? [self interactiveAncestorOf:logo] : (UIView *)win;

    if (self.recognizer.view == target) return;
    if (self.recognizer.view) {
        [self.recognizer.view removeGestureRecognizer:self.recognizer];
    }
    if (!self.recognizer) {
        self.recognizer = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(handleLongPress:)];
        self.recognizer.minimumPressDuration = kGHPressDuration;
        self.recognizer.cancelsTouchesInView = NO;
        self.recognizer.delaysTouchesBegan = NO;
        self.recognizer.delegate = self;
    }
    [target addGestureRecognizer:self.recognizer];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    CGPoint p = [g locationInView:g.view.window];
    UIView *logo = self.logoView;
    if (logo && logo.window) {
        CGRect f = [logo convertRect:logo.bounds toView:logo.window];
        return CGRectContainsPoint(CGRectInset(f, -kGHTouchSlop, -kGHTouchSlop), p);
    }
    return p.x <= kGHZoneMaxX && p.y >= kGHZoneMinY && p.y <= kGHZoneMaxY;
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;

    Class cls = NSClassFromString(@"SettingsViewController");
    if (!cls || ![cls isSubclassOfClass:UIViewController.class]) return;

    UIViewController *settings = [[cls alloc] init];
    UINavigationController *nav =
        [[UINavigationController alloc] initWithRootViewController:settings];

    UIViewController *top = g.view.window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if (!top) return;
    [top presentViewController:nav animated:YES completion:nil];
}

@end

__attribute__((constructor)) static void GHInit(void) {
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    GHLogoLongPress *h = GHLogoLongPress.shared;
    [nc addObserver:h selector:@selector(tick)
               name:UIApplicationDidFinishLaunchingNotification object:nil];
    [nc addObserver:h selector:@selector(tick)
               name:UISceneDidActivateNotification object:nil];
    [nc addObserver:h selector:@selector(tick)
               name:UIWindowDidBecomeKeyNotification object:nil];
}
