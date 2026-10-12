// =============================================================================
// Astral Cheat v2 — StandRise rework (private server)
// External TrollStore HUD · floating icon · red/green toggles · anti-record
// Classes from UnityFramework + global-metadata v31:
//   PlayerController, LocalPlayer, PlayerManager, AimController,
//   WeaponController, AntiCheatManager, CameraController, GetBoneTransform
// =============================================================================

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#include <cmath>
#include <vector>
#include <string>
#include <mutex>
#include <algorithm>
#include <cstdint>

#define ASTRAL_TG @"https://t.me/Astral_Cheats"

#pragma mark - Global state

static BOOL gRunning  = NO;
static BOOL gMenuOpen = NO;
static int  gMenuTab  = 0; // 0 ESP · 1 AIM · 2 MISC

static BOOL gEsp      = YES;
static BOOL gEspBox   = YES;
static BOOL gEspName  = YES;
static BOOL gEspHP    = YES;
static BOOL gEspDist  = YES;
static BOOL gEspSnap  = NO;

static BOOL gAim       = YES;
static BOOL gAimSilent = YES;
static BOOL gAimTeam   = YES;
static BOOL gAimFovDraw= NO;
static float gAimFov   = 120.f;

static BOOL gHideRec  = YES;  // hide HUD from screen recording / screenshots
static BOOL gAntiban  = YES;

#pragma mark - Math / entities (StandRise pipeline)

struct V3 { float x,y,z; V3(float x=0,float y=0,float z=0):x(x),y(y),z(z){}
    V3 operator-(const V3&o)const{return {x-o.x,y-o.y,z-o.z};}
    float len()const{return sqrtf(x*x+y*y+z*z);}
};
struct V2 { float x,y; };
struct M4 { float m[16]; };

struct Ent {
    V3 pos, head;
    float hp, maxHp, dist;
    int team;
    bool local, dead;
    std::string name;
};

static std::vector<Ent> gEnts;
static std::mutex gEntMtx;
static V3 gLocalPos;
static int gLocalTeam = -1;
static M4 gVM;

// Field offsets — re-derive with Il2CppDumper after game update
namespace Off {
    const uint32_t Transform_Pos   = 0x90;
    const uint32_t Player_Health   = 0x48;
    const uint32_t Player_MaxHP    = 0x4C;
    const uint32_t Player_Team     = 0x5C;
    const uint32_t Player_IsDead   = 0x60;
    const uint32_t Aim_Pitch       = 0x40;
    const uint32_t Aim_Yaw         = 0x44;
}

static bool W2S(const V3& w, V2& o, float sw, float sh) {
    const float* m = gVM.m;
    float cw = m[3]*w.x + m[7]*w.y + m[11]*w.z + m[15];
    if (cw < 0.01f) return false;
    float inv = 1.f / cw;
    float x = (m[0]*w.x + m[4]*w.y + m[8]*w.z + m[12]) * inv;
    float y = (m[1]*w.x + m[5]*w.y + m[9]*w.z + m[13]) * inv;
    o.x = (sw * 0.5f) * (1.f + x);
    o.y = (sh * 0.5f) * (1.f - y);
    return true;
}

// Called every frame when running. When injected into game / with memory R/W:
// walk PlayerManager -> PlayerController list, fill gEnts, gLocalPos, gVM.
static void StandRise_Tick() {
    // Placeholder: entity list empty until memory backend connected.
    // Target classes: PlayerController, LocalPlayer, AimController,
    // WeaponController, CameraController, AntiCheatManager.
}

static void StandRise_SilentAim(const Ent& t) {
    if (!gAim || !gAimSilent) return;
    V3 d = t.head - gLocalPos;
    float len = d.len();
    if (len < 0.01f) return;
    // pitch/yaw -> AimController fields (Off::Aim_Pitch / Aim_Yaw)
    (void)d;
}

#pragma mark - Secure floating window

@interface AstralWindow : UIWindow
@end
@implementation AstralWindow
- (BOOL)_isSecure { return gHideRec; }
- (BOOL)isSecure  { return gHideRec; }
- (BOOL)_canBecomeKeyWindow { return YES; }
@end

#pragma mark - HUD (FAB + scrollable menu + ESP draw)

@interface HUDView : UIView
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, strong) UIView *fab;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIView *panel;
- (void)startHUD;
- (void)stopHUD;
- (void)rebuildMenu;
@end

@implementation HUDView

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.userInteractionEnabled = YES;

    // --- FAB ---
    CGFloat fs = 56;
    self.fab = [[UIView alloc] initWithFrame:CGRectMake(f.size.width - fs - 16, f.size.height * 0.52, fs, fs)];
    self.fab.backgroundColor = [UIColor colorWithRed:0.07 green:0.16 blue:0.36 alpha:0.96];
    self.fab.layer.cornerRadius = fs / 2;
    self.fab.layer.borderWidth = 2.5;
    self.fab.layer.borderColor = [UIColor colorWithRed:0.3 green:0.7 blue:1 alpha:1].CGColor;
    self.fab.layer.shadowColor = [UIColor colorWithRed:0.2 green:0.5 blue:1 alpha:0.6].CGColor;
    self.fab.layer.shadowRadius = 8;
    self.fab.layer.shadowOpacity = 0.8;
    self.fab.hidden = YES;
    self.fab.userInteractionEnabled = YES;

    UILabel *fabL = [[UILabel alloc] initWithFrame:self.fab.bounds];
    fabL.text = @"A";
    fabL.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    fabL.textColor = [UIColor colorWithRed:0.55 green:0.88 blue:1 alpha:1];
    fabL.textAlignment = NSTextAlignmentCenter;
    fabL.tag = 50;
    [self.fab addSubview:fabL];
    [self.fab addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(fabTap)]];
    [self.fab addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(fabPan:)]];
    [self addSubview:self.fab];

    // --- Panel ---
    CGFloat mw = 300, mh = 400;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(28, 88, mw, mh)];
    self.panel.backgroundColor = [UIColor colorWithRed:0.04 green:0.07 blue:0.13 alpha:0.95];
    self.panel.layer.cornerRadius = 18;
    self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = [UIColor colorWithRed:0.2 green:0.5 blue:1 alpha:0.45].CGColor;
    self.panel.clipsToBounds = YES;
    self.panel.hidden = YES;
    [self addSubview:self.panel];

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, mw, 50)];
    header.backgroundColor = [UIColor colorWithRed:0.1 green:0.28 blue:0.6 alpha:0.4];
    [self.panel addSubview:header];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 13, 220, 24)];
    title.text = @"ASTRAL  ·  STANDRISE";
    title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    title.textColor = [UIColor colorWithRed:0.5 green:0.85 blue:1 alpha:1];
    [header addSubview:title];

    NSArray *tabs = @[@"ESP", @"AIM", @"MISC"];
    CGFloat tw = mw / 3.f;
    for (int i = 0; i < 3; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(tw * i, 50, tw, 34);
        [b setTitle:tabs[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        b.tag = 100 + i;
        [b addTarget:self action:@selector(tab:) forControlEvents:UIControlEventTouchUpInside];
        [self.panel addSubview:b];
    }

    self.scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 88, mw, mh - 88 - 26)];
    self.scroll.showsVerticalScrollIndicator = YES;
    self.scroll.alwaysBounceVertical = YES;
    [self.panel addSubview:self.scroll];

    UILabel *foot = [[UILabel alloc] initWithFrame:CGRectMake(0, mh - 24, mw, 18)];
    foot.text = @"t.me/Astral_Cheats  ·  v2.0";
    foot.font = [UIFont systemFontOfSize:10];
    foot.textColor = [UIColor colorWithRed:0.4 green:0.65 blue:0.9 alpha:0.85];
    foot.textAlignment = NSTextAlignmentCenter;
    [self.panel addSubview:foot];

    [self colorTabs];
    [self rebuildMenu];
    return self;
}

- (void)startHUD {
    gRunning = YES;
    gMenuOpen = NO;
    self.fab.hidden = NO;
    self.panel.hidden = YES;
    if (!self.link) {
        self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(frame:)];
        self.link.preferredFramesPerSecond = 60;
        [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)stopHUD {
    gRunning = NO;
    gMenuOpen = NO;
    self.fab.hidden = YES;
    self.panel.hidden = YES;
    [self.link invalidate];
    self.link = nil;
    [self setNeedsDisplay];
}

- (void)frame:(CADisplayLink *)l {
    if (!gRunning) return;
    StandRise_Tick();
    [self setNeedsDisplay];
}

#pragma mark FAB

- (void)fabTap {
    if (!gRunning) return;
    gMenuOpen = !gMenuOpen;
    self.panel.hidden = !gMenuOpen;
    if (gMenuOpen) [self rebuildMenu];
}

- (void)fabPan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self];
    CGPoint c = self.fab.center;
    c.x += t.x; c.y += t.y;
    CGFloat h = self.fab.bounds.size.width / 2;
    c.x = fmaxf(h, fminf(self.bounds.size.width - h, c.x));
    c.y = fmaxf(h + 48, fminf(self.bounds.size.height - h - 24, c.y));
    self.fab.center = c;
    [g setTranslation:CGPointZero inView:self];
}

#pragma mark Menu UI

- (void)tab:(UIButton *)b {
    gMenuTab = (int)(b.tag - 100);
    [self colorTabs];
    [self rebuildMenu];
}

- (void)colorTabs {
    for (int i = 0; i < 3; i++) {
        UIButton *b = (UIButton *)[self.panel viewWithTag:100 + i];
        BOOL on = (gMenuTab == i);
        [b setTitleColor:on ? [UIColor colorWithRed:0.4 green:0.8 blue:1 alpha:1]
                           : [UIColor colorWithWhite:0.5 alpha:1]
                 forState:UIControlStateNormal];
    }
}

- (UIView *)row:(NSString *)title on:(BOOL)on y:(CGFloat)y tag:(int)tag {
    CGFloat w = self.scroll.bounds.size.width > 0 ? self.scroll.bounds.size.width : 300;
    UIView *r = [[UIView alloc] initWithFrame:CGRectMake(0, y, w, 46)];
    r.tag = tag;
    r.userInteractionEnabled = YES;

    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(18, 0, w - 90, 46)];
    lab.text = title;
    lab.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    lab.textColor = [UIColor colorWithRed:0.92 green:0.95 blue:1 alpha:0.96];
    [r addSubview:lab];

    UIView *pill = [[UIView alloc] initWithFrame:CGRectMake(w - 58, 13, 42, 20)];
    pill.layer.cornerRadius = 10;
    pill.tag = 1;
    pill.backgroundColor = on ? [UIColor colorWithRed:0.12 green:0.78 blue:0.38 alpha:1]
                              : [UIColor colorWithRed:0.88 green:0.18 blue:0.22 alpha:1];
    [r addSubview:pill];

    [r addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rowTap:)]];
    return r;
}

- (void)rebuildMenu {
    for (UIView *v in [self.scroll.subviews copy]) [v removeFromSuperview];
    CGFloat y = 6;
    if (gMenuTab == 0) {
        [self.scroll addSubview:[self row:@"ESP" on:gEsp y:y tag:1]]; y += 46;
        [self.scroll addSubview:[self row:@"Box" on:gEspBox y:y tag:2]]; y += 46;
        [self.scroll addSubview:[self row:@"Name" on:gEspName y:y tag:3]]; y += 46;
        [self.scroll addSubview:[self row:@"Health" on:gEspHP y:y tag:4]]; y += 46;
        [self.scroll addSubview:[self row:@"Distance" on:gEspDist y:y tag:5]]; y += 46;
        [self.scroll addSubview:[self row:@"Snaplines" on:gEspSnap y:y tag:6]]; y += 46;
    } else if (gMenuTab == 1) {
        [self.scroll addSubview:[self row:@"Aimbot" on:gAim y:y tag:10]]; y += 46;
        [self.scroll addSubview:[self row:@"Silent Aim" on:gAimSilent y:y tag:11]]; y += 46;
        [self.scroll addSubview:[self row:@"Team Check" on:gAimTeam y:y tag:12]]; y += 46;
        [self.scroll addSubview:[self row:@"Draw FOV" on:gAimFovDraw y:y tag:13]]; y += 46;
    } else {
        [self.scroll addSubview:[self row:@"Hide Recording" on:gHideRec y:y tag:20]]; y += 46;
        [self.scroll addSubview:[self row:@"Antiban" on:gAntiban y:y tag:21]]; y += 46;
    }
    self.scroll.contentSize = CGSizeMake(self.scroll.bounds.size.width, y + 12);
}

- (void)rowTap:(UITapGestureRecognizer *)gr {
    int tag = (int)gr.view.tag;
    BOOL *p = NULL;
    switch (tag) {
        case 1: p=&gEsp; break; case 2: p=&gEspBox; break; case 3: p=&gEspName; break;
        case 4: p=&gEspHP; break; case 5: p=&gEspDist; break; case 6: p=&gEspSnap; break;
        case 10: p=&gAim; break; case 11: p=&gAimSilent; break; case 12: p=&gAimTeam; break;
        case 13: p=&gAimFovDraw; break;
        case 20: p=&gHideRec; break; case 21: p=&gAntiban; break;
        default: return;
    }
    *p = !*p;
    UIView *pill = [gr.view viewWithTag:1];
    pill.backgroundColor = *p ? [UIColor colorWithRed:0.12 green:0.78 blue:0.38 alpha:1]
                              : [UIColor colorWithRed:0.88 green:0.18 blue:0.22 alpha:1];
}

#pragma mark Draw ESP

- (void)drawRect:(CGRect)rect {
    if (!gRunning) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    CGFloat W = rect.size.width, H = rect.size.height;

    if (gEsp) {
        std::lock_guard<std::mutex> lk(gEntMtx);
        for (size_t ei = 0; ei < gEnts.size(); ei++) {
            const Ent& e = gEnts[ei];
            if (e.local || e.dead) continue;
            if (gAimTeam && e.team == gLocalTeam) continue;
            V2 feet, head;
            if (!W2S(e.pos, feet, W, H) || !W2S(e.head, head, W, H)) continue;
            float h = fabsf(feet.y - head.y), w = h * 0.45f;
            float x = head.x - w * 0.5f, y = head.y;
            if (gEspBox) {
                CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0.3 green:0.7 blue:1 alpha:0.95].CGColor);
                CGContextSetLineWidth(ctx, 1.5);
                CGContextStrokeRect(ctx, CGRectMake(x, y, w, h));
            }
            if (gEspHP) {
                float hp = fmaxf(0, fminf(1, e.hp / (e.maxHp > 0 ? e.maxHp : 100.f)));
                CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:1-hp green:hp blue:0.15 alpha:0.9].CGColor);
                CGContextFillRect(ctx, CGRectMake(x - 5, y + h * (1 - hp), 3, h * hp));
            }
            if (gEspName || gEspDist) {
                NSMutableString *s = [NSMutableString string];
                if (gEspName) [s appendFormat:@"%s", e.name.c_str()];
                if (gEspDist) [s appendFormat:@" [%.0fm]", e.dist];
                [s drawAtPoint:CGPointMake(x, y - 14) withAttributes:@{
                    NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightMedium],
                    NSForegroundColorAttributeName: [UIColor colorWithRed:0.8 green:0.92 blue:1 alpha:0.95]
                }];
            }
            if (gEspSnap) {
                CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0.25 green:0.55 blue:1 alpha:0.35].CGColor);
                CGContextSetLineWidth(ctx, 0.8);
                CGContextMoveToPoint(ctx, W * 0.5f, H);
                CGContextAddLineToPoint(ctx, feet.x, feet.y);
                CGContextStrokePath(ctx);
            }
        }
    }

    if (gAim && gAimFovDraw) {
        CGFloat r = gAimFov * 0.5f;
        CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0.3 green:0.65 blue:1 alpha:0.3].CGColor);
        CGContextSetLineWidth(ctx, 1);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(W*0.5f - r, H*0.5f - r, r*2, r*2));
    }
}

- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    if (!gRunning) return nil;
    if (gMenuOpen && CGRectContainsPoint(self.panel.frame, p))
        return [super hitTest:p withEvent:e];
    if (CGRectContainsPoint(self.fab.frame, p))
        return [super hitTest:p withEvent:e];
    if (gMenuOpen) {
        gMenuOpen = NO;
        self.panel.hidden = YES;
    }
    return nil; // pass touches to game
}

@end

#pragma mark - Launch VC

@interface LaunchVC : UIViewController
@property (nonatomic, strong) UIButton *btn;
@property (nonatomic, strong) UILabel *iosLab, *tgLab;
@property (nonatomic, strong) UIView *icon;
@property (nonatomic, copy) void (^onStart)(void);
@property (nonatomic, copy) void (^onStop)(void);
@end

@implementation LaunchVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.96 green:0.97 blue:0.99 alpha:1];

    self.iosLab = [UILabel new];
    self.iosLab.font = [UIFont systemFontOfSize:13];
    self.iosLab.textColor = [UIColor colorWithWhite:0.35 alpha:1];
    self.iosLab.textAlignment = NSTextAlignmentCenter;
    self.iosLab.text = [NSString stringWithFormat:@"iOS - %@", UIDevice.currentDevice.systemVersion];
    [self.view addSubview:self.iosLab];

    self.icon = [UIView new];
    self.icon.backgroundColor = [UIColor colorWithRed:0.05 green:0.12 blue:0.28 alpha:1];
    self.icon.layer.cornerRadius = 28;
    self.icon.layer.masksToBounds = YES;
    [self.view addSubview:self.icon];
    UILabel *a = [UILabel new];
    a.tag = 99; a.text = @"A";
    a.font = [UIFont systemFontOfSize:36 weight:UIFontWeightBold];
    a.textColor = [UIColor colorWithRed:0.45 green:0.8 blue:1 alpha:1];
    a.textAlignment = NSTextAlignmentCenter;
    [self.icon addSubview:a];

    self.btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.btn setTitle:@"Start" forState:UIControlStateNormal];
    self.btn.titleLabel.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    [self.btn setTitleColor:[UIColor colorWithRed:0.08 green:0.1 blue:0.14 alpha:1] forState:UIControlStateNormal];
    [self.btn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.btn];

    self.tgLab = [UILabel new];
    self.tgLab.text = @"t.me/Astral_Cheats";
    self.tgLab.font = [UIFont systemFontOfSize:13];
    self.tgLab.textColor = [UIColor colorWithWhite:0.4 alpha:1];
    self.tgLab.textAlignment = NSTextAlignmentCenter;
    self.tgLab.userInteractionEnabled = YES;
    [self.tgLab addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openTG)]];
    [self.view addSubview:self.tgLab];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
    self.iosLab.frame = CGRectMake(0, H*0.14f, W, 20);
    CGFloat is = 100;
    self.icon.frame = CGRectMake((W-is)/2, H*0.30f, is, is);
    [self.icon viewWithTag:99].frame = self.icon.bounds;
    self.btn.frame = CGRectMake(40, H*0.50f, W-80, 50);
    self.tgLab.frame = CGRectMake(0, H*0.50f+56, W, 22);
}

- (void)toggle {
    if (!gRunning) {
        [self.btn setTitle:@"Stop" forState:UIControlStateNormal];
        if (self.onStart) self.onStart();
    } else {
        [self.btn setTitle:@"Start" forState:UIControlStateNormal];
        if (self.onStop) self.onStop();
    }
}

- (void)openTG {
    NSURL *u = [NSURL URLWithString:ASTRAL_TG];
    if (u) [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];
}

@end

#pragma mark - App

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *mainWindow;
@property (strong, nonatomic) AstralWindow *hudWindow;
@property (strong, nonatomic) LaunchVC *launch;
@property (strong, nonatomic) HUDView *hud;
@property (strong, nonatomic) AVAudioPlayer *silentPlayer; // keep alive in bg
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    CGRect b = UIScreen.mainScreen.bounds;

    self.mainWindow = [[UIWindow alloc] initWithFrame:b];
    self.mainWindow.backgroundColor = UIColor.whiteColor;
    self.launch = [LaunchVC new];
    self.mainWindow.rootViewController = self.launch;
    [self.mainWindow makeKeyAndVisible];

    self.hudWindow = [[AstralWindow alloc] initWithFrame:b];
    self.hudWindow.backgroundColor = UIColor.clearColor;
    self.hudWindow.windowLevel = UIWindowLevelStatusBar + 100;
    self.hudWindow.hidden = YES;
    UIViewController *hr = [UIViewController new];
    hr.view.backgroundColor = UIColor.clearColor;
    self.hudWindow.rootViewController = hr;
    self.hud = [[HUDView alloc] initWithFrame:b];
    [hr.view addSubview:self.hud];

    // silent audio session helps process stay alive longer in background
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
                                     withOptions:AVAudioSessionCategoryOptionMixWithOthers
                                           error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];

    __weak AppDelegate *w = self;
    self.launch.onStart = ^{
        w.hudWindow.hidden = NO;
        [w.hudWindow makeKeyAndVisible];
        [w.hud startHUD];
        [app beginBackgroundTaskWithExpirationHandler:nil];
    };
    self.launch.onStop = ^{
        [w.hud stopHUD];
        w.hudWindow.hidden = YES;
        [w.mainWindow makeKeyAndVisible];
    };
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    if (!gRunning) return;
    __block UIBackgroundTaskIdentifier t = [application beginBackgroundTaskWithExpirationHandler:^{
        [application endBackgroundTask:t];
        t = UIBackgroundTaskInvalid;
    }];
}

@end

@interface HUDMainApplication : UIApplication
@end
@implementation HUDMainApplication
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv,
            NSStringFromClass([HUDMainApplication class]),
            NSStringFromClass([AppDelegate class]));
    }
}
