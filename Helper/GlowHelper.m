// GlowHelper - companion dylib for Glow for Facebook.
// Adds a second entry point to Glow settings: long-press on the
// Facebook logo area in the app's top bar (top-left zone).
// The original long-press-on-tab trigger inside Glow.dylib is
// left untouched.

#import <UIKit/UIKit.h>

static const NSTimeInterval kGHPressDuration = 3.0;
static const NSTimeInterval kGHScanInterval = 5.0;
static const NSTimeInterval kGHFirstDelay = 3.0;
static const CGFloat kGHZoneMaxX = 170.0;
static const CGFloat kGHZoneMinY = 40.0;
static const CGFloat kGHZoneMaxY = 115.0;

static UIWindow *GHKeyWindow(void) {
    UIApplication *app = UIApplication.sharedApplication;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        if (scene.activationState == UISceneActivationStateUnattached) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) return w;
        }
    }
    return nil;
}

@interface GHLogoLongPress : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UILongPressGestureRecognizer *recognizer;
@property (nonatomic, strong) NSTimer *timer;
+ (instancetype)shared;
- (void)start;
@end

@implementation GHLogoLongPress

+ (instancetype)shared {
    static GHLogoLongPress *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [GHLogoLongPress new]; });
    return s;
}

- (void)start {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.timer) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kGHFirstDelay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self attach]; });
        self.timer = [NSTimer scheduledTimerWithTimeInterval:kGHScanInterval
                                                     repeats:YES
                                                       block:^(NSTimer *t) { [self attach]; }];
        self.timer.tolerance = 1.0;
    });
}

- (void)attach {
    UIWindow *win = GHKeyWindow();
    if (!win) return;

    if (self.recognizer.view == win) return;
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
    [win addGestureRecognizer:self.recognizer];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    CGPoint p = [g locationInView:g.view];
    return p.x <= kGHZoneMaxX && p.y >= kGHZoneMinY && p.y <= kGHZoneMaxY;
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;

    Class cls = NSClassFromString(@"SettingsViewController");
    if (!cls || ![cls isSubclassOfClass:UIViewController.class]) return;

    UIViewController *settings = [[cls alloc] init];
    UINavigationController *nav =
        [[UINavigationController alloc] initWithRootViewController:settings];

    UIWindow *win = [g.view isKindOfClass:UIWindow.class] ? (UIWindow *)g.view : g.view.window;
    UIViewController *top = win.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if (!top) return;
    [top presentViewController:nav animated:YES completion:nil];
}

@end

__attribute__((constructor)) static void GHInit(void) {
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    GHLogoLongPress *h = GHLogoLongPress.shared;
    [nc addObserver:h selector:@selector(start)
               name:UIApplicationDidFinishLaunchingNotification object:nil];
    [nc addObserver:h selector:@selector(start)
               name:UISceneDidActivateNotification object:nil];
    [nc addObserver:h selector:@selector(start)
               name:UIWindowDidBecomeKeyNotification object:nil];
}
