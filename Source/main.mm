// Astral Cheat v2.2 — modern menu, draggable panel, configs, secure recording hide
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#include <cmath>
#include <vector>
#include <string>
#include <mutex>

#define TG @"https://t.me/Astral_Cheats"
#define CFG_KEY @"AstralCheatConfig_v22"

static BOOL gRunning=NO, gMenuOpen=NO;
static int gTab=0;

static BOOL gEsp=YES, gEspBox=YES, gEspName=YES, gEspHP=YES, gEspDist=YES, gEspSnap=NO;
static BOOL gAim=YES, gAimSilent=YES, gAimTeam=YES, gAimFov=NO;
static BOOL gHideRec=YES, gAntiban=YES;

struct V3{float x,y,z; V3(float x=0,float y=0,float z=0):x(x),y(y),z(z){}};
struct V2{float x,y;};
struct M4{float m[16];};
struct Ent{V3 pos,head; float hp,maxHp,dist; int team; bool local,dead; std::string name;};
static std::vector<Ent> gEnts;
static std::mutex gEntMtx;
static V3 gLocalPos; static int gLocalTeam=-1; static M4 gVM;

static bool W2S(const V3& w, V2& o, float sw, float sh){
    const float* m=gVM.m;
    float cw=m[3]*w.x+m[7]*w.y+m[11]*w.z+m[15];
    if(cw<0.01f) return false;
    float inv=1.f/cw;
    o.x=(sw*0.5f)*(1.f+(m[0]*w.x+m[4]*w.y+m[8]*w.z+m[12])*inv);
    o.y=(sh*0.5f)*(1.f-(m[1]*w.x+m[5]*w.y+m[9]*w.z+m[13])*inv);
    return true;
}

static void SaveCfg(){
    NSDictionary *d=@{
        @"esp":@(gEsp),@"box":@(gEspBox),@"name":@(gEspName),@"hp":@(gEspHP),
        @"dist":@(gEspDist),@"snap":@(gEspSnap),
        @"aim":@(gAim),@"silent":@(gAimSilent),@"team":@(gAimTeam),@"fov":@(gAimFov),
        @"hideRec":@(gHideRec),@"antiban":@(gAntiban),@"tab":@(gTab)
    };
    [[NSUserDefaults standardUserDefaults] setObject:d forKey:CFG_KEY];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
static void LoadCfg(){
    NSDictionary *d=[[NSUserDefaults standardUserDefaults] objectForKey:CFG_KEY];
    if(![d isKindOfClass:[NSDictionary class]]) return;
    gEsp=[d[@"esp"] boolValue]; gEspBox=[d[@"box"] boolValue]; gEspName=[d[@"name"] boolValue];
    gEspHP=[d[@"hp"] boolValue]; gEspDist=[d[@"dist"] boolValue]; gEspSnap=[d[@"snap"] boolValue];
    gAim=[d[@"aim"] boolValue]; gAimSilent=[d[@"silent"] boolValue]; gAimTeam=[d[@"team"] boolValue];
    gAimFov=[d[@"fov"] boolValue]; gHideRec=[d[@"hideRec"] boolValue]; gAntiban=[d[@"antiban"] boolValue];
    gTab=[d[@"tab"] intValue];
}

#pragma mark - Secure window

@interface AstralWindow : UIWindow
@end
@implementation AstralWindow
- (BOOL)_isSecure { return gHideRec; }
- (BOOL)isSecure { return gHideRec; }
- (BOOL)_shouldCreateContextAsSecure { return gHideRec; }
- (BOOL)_canBecomeKeyWindow { return YES; }
// Force secure layer for ReplayKit / screenshots
+ (void)applySecureToView:(UIView *)v {
    if (!gHideRec) return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    SEL s1 = NSSelectorFromString(@"_setSecure:");
    SEL s2 = NSSelectorFromString(@"setSecure:");
    if ([v respondsToSelector:s1]) [v performSelector:s1 withObject:@YES];
    else if ([v respondsToSelector:s2]) [v performSelector:s2 withObject:@YES];
#pragma clang diagnostic pop
    // Also try CALayer secure
    CALayer *layer = v.layer;
    if ([layer respondsToSelector:NSSelectorFromString(@"setDisableActions:")]) {
        // keep
    }
}
@end

#pragma mark - Modern HUD

@interface HUDView : UIView
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, strong) UIView *fab;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIView *dragBar;
- (void)startHUD;
- (void)stopHUD;
- (void)rebuild;
- (void)refreshSecure;
@end

@implementation HUDView

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.userInteractionEnabled = YES;
    LoadCfg();

    // FAB
    CGFloat s = 56;
    self.fab = [[UIView alloc] initWithFrame:CGRectMake(f.size.width-s-16, f.size.height*0.55, s, s)];
    self.fab.backgroundColor = [UIColor colorWithRed:0.08 green:0.16 blue:0.34 alpha:0.98];
    self.fab.layer.cornerRadius = s/2;
    self.fab.layer.borderWidth = 2;
    self.fab.layer.borderColor = [UIColor colorWithRed:0.35 green:0.72 blue:1 alpha:1].CGColor;
    self.fab.layer.shadowColor = [UIColor colorWithRed:0.2 green:0.5 blue:1 alpha:1].CGColor;
    self.fab.layer.shadowRadius = 12;
    self.fab.layer.shadowOpacity = 0.65;
    self.fab.layer.shadowOffset = CGSizeZero;
    self.fab.hidden = YES;
    UILabel *fl = [[UILabel alloc] initWithFrame:self.fab.bounds];
    fl.text = @"A"; fl.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    fl.textColor = [UIColor colorWithRed:0.55 green:0.9 blue:1 alpha:1];
    fl.textAlignment = NSTextAlignmentCenter;
    [self.fab addSubview:fl];
    [self.fab addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(fabTap)]];
    [self.fab addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(fabPan:)]];
    [self addSubview:self.fab];

    // Panel — modern card
    CGFloat mw = 300, mh = 440;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake((f.size.width-mw)/2, 100, mw, mh)];
    self.panel.backgroundColor = [UIColor colorWithRed:0.07 green:0.09 blue:0.14 alpha:0.97];
    self.panel.layer.cornerRadius = 22;
    self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.08].CGColor;
    self.panel.layer.shadowColor = [UIColor blackColor].CGColor;
    self.panel.layer.shadowRadius = 24;
    self.panel.layer.shadowOpacity = 0.5;
    self.panel.layer.shadowOffset = CGSizeMake(0, 8);
    self.panel.clipsToBounds = NO;
    self.panel.hidden = YES;
    [self addSubview:self.panel];

    // Inner clip container
    UIView *inner = [[UIView alloc] initWithFrame:self.panel.bounds];
    inner.layer.cornerRadius = 22;
    inner.clipsToBounds = YES;
    inner.tag = 99;
    inner.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.panel addSubview:inner];

    // Drag handle area
    self.dragBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, mw, 56)];
    self.dragBar.backgroundColor = [UIColor colorWithRed:0.12 green:0.18 blue:0.32 alpha:1];
    [inner addSubview:self.dragBar];
    // pill indicator
    UIView *pill = [[UIView alloc] initWithFrame:CGRectMake((mw-36)/2, 8, 36, 4)];
    pill.backgroundColor = [UIColor colorWithWhite:1 alpha:0.25];
    pill.layer.cornerRadius = 2;
    [self.dragBar addSubview:pill];
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 20, mw-32, 28)];
    title.text = @"Astral";
    title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    [self.dragBar addSubview:title];
    UIPanGestureRecognizer *panelPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panelPan:)];
    [self.dragBar addGestureRecognizer:panelPan];

    // Tabs
    NSArray *tabs = @[@"ESP", @"AIM", @"MISC"];
    CGFloat tw = mw/3.f;
    for (int i=0;i<3;i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(tw*i, 56, tw, 40);
        [b setTitle:tabs[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        b.tag = 100+i;
        [b addTarget:self action:@selector(tab:) forControlEvents:UIControlEventTouchUpInside];
        [inner addSubview:b];
    }
    // underline
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 95, mw, 0.5)];
    line.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    line.tag = 80;
    [inner addSubview:line];

    self.scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 100, mw, mh-100-56)];
    self.scroll.alwaysBounceVertical = YES;
    self.scroll.showsVerticalScrollIndicator = YES;
    [inner addSubview:self.scroll];

    // Bottom actions: Save / Load
    UIView *bottom = [[UIView alloc] initWithFrame:CGRectMake(0, mh-56, mw, 56)];
    bottom.backgroundColor = [UIColor colorWithRed:0.09 green:0.11 blue:0.16 alpha:1];
    bottom.tag = 70;
    [inner addSubview:bottom];

    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    saveBtn.frame = CGRectMake(16, 10, (mw-40)/2, 36);
    [saveBtn setTitle:@"Save Config" forState:UIControlStateNormal];
    saveBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [saveBtn setTitleColor:[UIColor colorWithRed:0.4 green:0.85 blue:1 alpha:1] forState:UIControlStateNormal];
    saveBtn.backgroundColor = [UIColor colorWithRed:0.15 green:0.25 blue:0.45 alpha:1];
    saveBtn.layer.cornerRadius = 10;
    [saveBtn addTarget:self action:@selector(saveCfg) forControlEvents:UIControlEventTouchUpInside];
    [bottom addSubview:saveBtn];

    UIButton *loadBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    loadBtn.frame = CGRectMake(16+(mw-40)/2+8, 10, (mw-40)/2, 36);
    [loadBtn setTitle:@"Load Config" forState:UIControlStateNormal];
    loadBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [loadBtn setTitleColor:[UIColor colorWithRed:0.7 green:0.8 blue:0.95 alpha:1] forState:UIControlStateNormal];
    loadBtn.backgroundColor = [UIColor colorWithRed:0.18 green:0.2 blue:0.28 alpha:1];
    loadBtn.layer.cornerRadius = 10;
    [loadBtn addTarget:self action:@selector(loadCfg) forControlEvents:UIControlEventTouchUpInside];
    [bottom addSubview:loadBtn];

    [self colorTabs];
    [self rebuild];
    return self;
}

- (void)refreshSecure {
    [AstralWindow applySecureToView:self];
    [AstralWindow applySecureToView:self.panel];
    [AstralWindow applySecureToView:self.fab];
    UIWindow *w = self.window;
    if ([w isKindOfClass:[AstralWindow class]]) {
        // trigger secure getters
        (void)[(AstralWindow *)w isSecure];
    }
}

- (void)startHUD {
    gRunning=YES; gMenuOpen=NO;
    self.fab.hidden=NO; self.panel.hidden=YES;
    [self refreshSecure];
    if (!self.link) {
        self.link=[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        self.link.preferredFramesPerSecond=60;
        [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}
- (void)stopHUD {
    gRunning=NO; gMenuOpen=NO;
    self.fab.hidden=YES; self.panel.hidden=YES;
    [self.link invalidate]; self.link=nil;
    [self setNeedsDisplay];
}
- (void)tick:(CADisplayLink *)l { if(gRunning) [self setNeedsDisplay]; }

- (void)fabTap {
    if (!gRunning) return;
    gMenuOpen = !gMenuOpen;
    self.panel.hidden = !gMenuOpen;
    if (gMenuOpen) { [self rebuild]; [self refreshSecure]; }
}
- (void)fabPan:(UIPanGestureRecognizer *)g {
    CGPoint t=[g translationInView:self];
    CGPoint c=self.fab.center;
    c.x+=t.x; c.y+=t.y;
    CGFloat h=self.fab.bounds.size.width/2;
    c.x=fmaxf(h,fminf(self.bounds.size.width-h,c.x));
    c.y=fmaxf(h+48,fminf(self.bounds.size.height-h-24,c.y));
    self.fab.center=c;
    [g setTranslation:CGPointZero inView:self];
}
- (void)panelPan:(UIPanGestureRecognizer *)g {
    CGPoint t=[g translationInView:self];
    CGRect f=self.panel.frame;
    f.origin.x+=t.x; f.origin.y+=t.y;
    // clamp
    f.origin.x=fmaxf(-f.size.width*0.5f, fminf(self.bounds.size.width-f.size.width*0.5f, f.origin.x));
    f.origin.y=fmaxf(40, fminf(self.bounds.size.height-80, f.origin.y));
    self.panel.frame=f;
    [g setTranslation:CGPointZero inView:self];
}

- (void)tab:(UIButton *)b {
    gTab=(int)(b.tag-100);
    [self colorTabs];
    [self rebuild];
}
- (void)colorTabs {
    for (int i=0;i<3;i++) {
        UIButton *b=(UIButton *)[[self.panel viewWithTag:99] viewWithTag:100+i];
        BOOL on=(gTab==i);
        [b setTitleColor:on?[UIColor colorWithRed:0.4 green:0.8 blue:1 alpha:1]:[UIColor colorWithWhite:0.45 alpha:1]
                forState:UIControlStateNormal];
    }
}

- (UIView *)row:(NSString *)title on:(BOOL)on y:(CGFloat)y tag:(int)tag {
    CGFloat w=self.scroll.bounds.size.width>10?self.scroll.bounds.size.width:300;
    UIView *r=[[UIView alloc] initWithFrame:CGRectMake(0,y,w,52)];
    r.tag=tag; r.userInteractionEnabled=YES;

    UILabel *lab=[[UILabel alloc] initWithFrame:CGRectMake(20,0,w-90,52)];
    lab.text=title;
    lab.font=[UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    lab.textColor=[UIColor colorWithWhite:0.95 alpha:1];
    [r addSubview:lab];

    // modern switch look
    UIView *track=[[UIView alloc] initWithFrame:CGRectMake(w-68,16,48,24)];
    track.layer.cornerRadius=12;
    track.tag=1;
    track.backgroundColor=on?[UIColor colorWithRed:0.15 green:0.75 blue:0.4 alpha:1]
                             :[UIColor colorWithRed:0.35 green:0.2 blue:0.22 alpha:1];
    [r addSubview:track];
    UIView *knob=[[UIView alloc] initWithFrame:CGRectMake(on?26:2,2,20,20)];
    knob.backgroundColor=[UIColor whiteColor];
    knob.layer.cornerRadius=10;
    knob.tag=2;
    knob.layer.shadowColor=[UIColor blackColor].CGColor;
    knob.layer.shadowOpacity=0.25;
    knob.layer.shadowRadius=2;
    [track addSubview:knob];

    [r addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rowTap:)]];
    return r;
}

- (void)rebuild {
    for (UIView *v in [self.scroll.subviews copy]) [v removeFromSuperview];
    CGFloat y=6;
    if (gTab==0) {
        [self.scroll addSubview:[self row:@"ESP" on:gEsp y:y tag:1]]; y+=52;
        [self.scroll addSubview:[self row:@"Box" on:gEspBox y:y tag:2]]; y+=52;
        [self.scroll addSubview:[self row:@"Name" on:gEspName y:y tag:3]]; y+=52;
        [self.scroll addSubview:[self row:@"Health" on:gEspHP y:y tag:4]]; y+=52;
        [self.scroll addSubview:[self row:@"Distance" on:gEspDist y:y tag:5]]; y+=52;
        [self.scroll addSubview:[self row:@"Snaplines" on:gEspSnap y:y tag:6]]; y+=52;
    } else if (gTab==1) {
        [self.scroll addSubview:[self row:@"Aimbot" on:gAim y:y tag:10]]; y+=52;
        [self.scroll addSubview:[self row:@"Silent Aim" on:gAimSilent y:y tag:11]]; y+=52;
        [self.scroll addSubview:[self row:@"Team Check" on:gAimTeam y:y tag:12]]; y+=52;
        [self.scroll addSubview:[self row:@"Draw FOV" on:gAimFov y:y tag:13]]; y+=52;
    } else {
        [self.scroll addSubview:[self row:@"Hide Recording" on:gHideRec y:y tag:20]]; y+=52;
        [self.scroll addSubview:[self row:@"Antiban" on:gAntiban y:y tag:21]]; y+=52;
    }
    self.scroll.contentSize=CGSizeMake(self.scroll.bounds.size.width,y+12);
}

- (void)rowTap:(UITapGestureRecognizer *)gr {
    int tag=(int)gr.view.tag;
    BOOL *p=NULL;
    switch(tag){
        case 1:p=&gEsp;break;case 2:p=&gEspBox;break;case 3:p=&gEspName;break;
        case 4:p=&gEspHP;break;case 5:p=&gEspDist;break;case 6:p=&gEspSnap;break;
        case 10:p=&gAim;break;case 11:p=&gAimSilent;break;case 12:p=&gAimTeam;break;
        case 13:p=&gAimFov;break;case 20:p=&gHideRec;break;case 21:p=&gAntiban;break;
        default:return;
    }
    *p=!*p;
    UIView *track=[gr.view viewWithTag:1];
    UIView *knob=[track viewWithTag:2];
    track.backgroundColor=*p?[UIColor colorWithRed:0.15 green:0.75 blue:0.4 alpha:1]
                             :[UIColor colorWithRed:0.35 green:0.2 blue:0.22 alpha:1];
    [UIView animateWithDuration:0.15 animations:^{
        CGRect kf=knob.frame;
        kf.origin.x=*p?26:2;
        knob.frame=kf;
    }];
    if (tag==20) [self refreshSecure]; // hide recording toggled
    SaveCfg(); // auto-save on toggle
}

- (void)saveCfg {
    SaveCfg();
    UILabel *toast=[[UILabel alloc] initWithFrame:CGRectMake(40,self.panel.bounds.size.height/2-18,self.panel.bounds.size.width-80,36)];
    toast.text=@"Config saved";
    toast.textAlignment=NSTextAlignmentCenter;
    toast.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    toast.textColor=[UIColor whiteColor];
    toast.backgroundColor=[UIColor colorWithRed:0.1 green:0.55 blue:0.3 alpha:0.95];
    toast.layer.cornerRadius=10; toast.clipsToBounds=YES;
    toast.tag=55;
    [[self.panel viewWithTag:99] addSubview:toast];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[self.panel viewWithTag:99] viewWithTag:55].hidden=YES;
        [[[self.panel viewWithTag:99] viewWithTag:55] removeFromSuperview];
    });
}
- (void)loadCfg {
    LoadCfg();
    [self colorTabs];
    [self rebuild];
    [self refreshSecure];
    UILabel *toast=[[UILabel alloc] initWithFrame:CGRectMake(40,self.panel.bounds.size.height/2-18,self.panel.bounds.size.width-80,36)];
    toast.text=@"Config loaded";
    toast.textAlignment=NSTextAlignmentCenter;
    toast.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    toast.textColor=[UIColor whiteColor];
    toast.backgroundColor=[UIColor colorWithRed:0.15 green:0.35 blue:0.65 alpha:0.95];
    toast.layer.cornerRadius=10; toast.clipsToBounds=YES;
    toast.tag=56;
    [[self.panel viewWithTag:99] addSubview:toast];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[[self.panel viewWithTag:99] viewWithTag:56] removeFromSuperview];
    });
}

- (void)drawRect:(CGRect)rect {
    if (!gRunning||!gEsp) return;
    CGContextRef ctx=UIGraphicsGetCurrentContext();
    if (!ctx) return;
    CGFloat W=rect.size.width,H=rect.size.height;
    std::lock_guard<std::mutex> lk(gEntMtx);
    for (size_t i=0;i<gEnts.size();i++) {
        const Ent& e=gEnts[i];
        if (e.local||e.dead) continue;
        if (gAimTeam&&e.team==gLocalTeam) continue;
        V2 feet,head;
        if (!W2S(e.pos,feet,W,H)||!W2S(e.head,head,W,H)) continue;
        float h=fabsf(feet.y-head.y),w=h*0.45f,x=head.x-w*0.5f,y=head.y;
        if (gEspBox) {
            CGContextSetStrokeColorWithColor(ctx,[UIColor colorWithRed:0.3 green:0.7 blue:1 alpha:0.95].CGColor);
            CGContextSetLineWidth(ctx,1.5);
            CGContextStrokeRect(ctx,CGRectMake(x,y,w,h));
        }
        if (gEspHP) {
            float hp=fmaxf(0,fminf(1,e.hp/(e.maxHp>0?e.maxHp:100.f)));
            CGContextSetFillColorWithColor(ctx,[UIColor colorWithRed:1-hp green:hp blue:0.15 alpha:0.9].CGColor);
            CGContextFillRect(ctx,CGRectMake(x-5,y+h*(1-hp),3,h*hp));
        }
        if (gEspName||gEspDist) {
            NSMutableString *s=[NSMutableString string];
            if (gEspName) [s appendFormat:@"%s",e.name.c_str()];
            if (gEspDist) [s appendFormat:@" [%.0fm]",e.dist];
            [s drawAtPoint:CGPointMake(x,y-14) withAttributes:@{
                NSFontAttributeName:[UIFont systemFontOfSize:10 weight:UIFontWeightMedium],
                NSForegroundColorAttributeName:[UIColor colorWithRed:0.8 green:0.92 blue:1 alpha:0.95]
            }];
        }
        if (gEspSnap) {
            CGContextSetStrokeColorWithColor(ctx,[UIColor colorWithRed:0.25 green:0.55 blue:1 alpha:0.35].CGColor);
            CGContextSetLineWidth(ctx,0.8);
            CGContextMoveToPoint(ctx,W*0.5f,H);
            CGContextAddLineToPoint(ctx,feet.x,feet.y);
            CGContextStrokePath(ctx);
        }
    }
}

- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    if (!gRunning) return nil;
    if (gMenuOpen && CGRectContainsPoint(self.panel.frame,p)) return [super hitTest:p withEvent:e];
    if (CGRectContainsPoint(self.fab.frame,p)) return [super hitTest:p withEvent:e];
    if (gMenuOpen) { gMenuOpen=NO; self.panel.hidden=YES; }
    return nil;
}
@end

#pragma mark - Launch

@interface LaunchVC : UIViewController
@property (nonatomic,strong) UIButton *btn;
@property (nonatomic,strong) UILabel *iosLab,*tgLab;
@property (nonatomic,strong) UIImageView *iconView;
@property (nonatomic,copy) void (^onStart)(void);
@property (nonatomic,copy) void (^onStop)(void);
@end
@implementation LaunchVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=[UIColor colorWithRed:0.97 green:0.97 blue:0.99 alpha:1];
    self.iosLab=[UILabel new];
    self.iosLab.font=[UIFont systemFontOfSize:13];
    self.iosLab.textColor=[UIColor colorWithWhite:0.35 alpha:1];
    self.iosLab.textAlignment=NSTextAlignmentCenter;
    self.iosLab.text=[NSString stringWithFormat:@"iOS - %@",UIDevice.currentDevice.systemVersion];
    [self.view addSubview:self.iosLab];
    UIImage *img=[UIImage imageNamed:@"icon.png"];
    if (!img) {
        NSString *p=[[NSBundle mainBundle] pathForResource:@"icon" ofType:@"png"];
        if (p) img=[UIImage imageWithContentsOfFile:p];
    }
    self.iconView=[[UIImageView alloc] initWithImage:img];
    self.iconView.contentMode=UIViewContentModeScaleAspectFill;
    self.iconView.clipsToBounds=YES;
    self.iconView.layer.cornerRadius=24;
    self.iconView.backgroundColor=[UIColor colorWithRed:0.05 green:0.12 blue:0.28 alpha:1];
    [self.view addSubview:self.iconView];
    self.btn=[UIButton buttonWithType:UIButtonTypeSystem];
    [self.btn setTitle:@"Start" forState:UIControlStateNormal];
    self.btn.titleLabel.font=[UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    [self.btn setTitleColor:[UIColor colorWithRed:0.08 green:0.1 blue:0.14 alpha:1] forState:UIControlStateNormal];
    [self.btn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.btn];
    self.tgLab=[UILabel new];
    self.tgLab.text=@"t.me/Astral_Cheats";
    self.tgLab.font=[UIFont systemFontOfSize:13];
    self.tgLab.textColor=[UIColor colorWithWhite:0.4 alpha:1];
    self.tgLab.textAlignment=NSTextAlignmentCenter;
    self.tgLab.userInteractionEnabled=YES;
    [self.tgLab addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openTG)]];
    [self.view addSubview:self.tgLab];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat W=self.view.bounds.size.width,H=self.view.bounds.size.height;
    self.iosLab.frame=CGRectMake(0,H*0.14f,W,20);
    CGFloat is=100;
    self.iconView.frame=CGRectMake((W-is)/2,H*0.28f,is,is);
    self.btn.frame=CGRectMake(40,H*0.48f,W-80,50);
    self.tgLab.frame=CGRectMake(0,H*0.48f+56,W,22);
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
    NSURL *u=[NSURL URLWithString:TG];
    if (u) [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:nil];
}
@end

#pragma mark - App

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong,nonatomic) UIWindow *mainWindow;
@property (strong,nonatomic) AstralWindow *hudWindow;
@property (strong,nonatomic) LaunchVC *launch;
@property (strong,nonatomic) HUDView *hud;
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    LoadCfg();
    CGRect b=UIScreen.mainScreen.bounds;
    self.mainWindow=[[UIWindow alloc] initWithFrame:b];
    self.mainWindow.backgroundColor=UIColor.whiteColor;
    self.launch=[LaunchVC new];
    self.mainWindow.rootViewController=self.launch;
    [self.mainWindow makeKeyAndVisible];

    self.hudWindow=[[AstralWindow alloc] initWithFrame:b];
    self.hudWindow.backgroundColor=UIColor.clearColor;
    self.hudWindow.windowLevel=UIWindowLevelStatusBar+1000;
    self.hudWindow.hidden=YES;
    UIViewController *hr=[UIViewController new];
    hr.view.backgroundColor=UIColor.clearColor;
    self.hudWindow.rootViewController=hr;
    self.hud=[[HUDView alloc] initWithFrame:b];
    [hr.view addSubview:self.hud];

    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
                                     withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];

    __weak AppDelegate *w=self;
    self.launch.onStart=^{
        w.hudWindow.windowLevel=UIWindowLevelStatusBar+1000;
        w.hudWindow.hidden=NO;
        [w.hudWindow makeKeyAndVisible];
        [w.hud startHUD];
        [w.hud refreshSecure];
        [app beginBackgroundTaskWithExpirationHandler:nil];
    };
    self.launch.onStop=^{
        [w.hud stopHUD];
        w.hudWindow.hidden=YES;
        [w.mainWindow makeKeyAndVisible];
    };
    return YES;
}
- (void)applicationDidEnterBackground:(UIApplication *)application {
    if (!gRunning) return;
    self.hudWindow.hidden=NO;
    self.hudWindow.windowLevel=UIWindowLevelStatusBar+1000;
    __block UIBackgroundTaskIdentifier t=[application beginBackgroundTaskWithExpirationHandler:^{
        [application endBackgroundTask:t]; t=UIBackgroundTaskInvalid;
    }];
}
- (void)applicationDidBecomeActive:(UIApplication *)application {
    if (gRunning) {
        self.hudWindow.hidden=NO;
        [self.hudWindow makeKeyAndVisible];
        [self.hud refreshSecure];
    }
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
