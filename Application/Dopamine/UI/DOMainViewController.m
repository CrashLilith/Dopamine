//
//  DOMainViewController.m
//  Dopamine
//
//  Created by tomt000 on 08/01/2024.
//

#import "DOMainViewController.h"
#import "DOUIManager.h"
#import "DOEnvironmentManager.h"
#import "DOJailbreaker.h"
#import "DOGlobalAppearance.h"
#import "DOActionMenuButton.h"
#import "DOUpdateViewController.h"
#import "DOLogCrashViewController.h"
#import <pthread.h>
#import <sys/sysctl.h>
#import <libjailbreak/libjailbreak.h>
#import <WebKit/WebKit.h>

// Neon's respring method (ported from mond/helpers/utils.swift).
// GPU-pressure via perspective + backdrop-filter in WKWebView. Must stay
// visible and full-screen: hidden / 1x1 views skip painting so nothing happens.
static NSString *DORespringHTML(void) {
    return @"<!DOCTYPE html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>"
    "<body style='margin:0;background:#000'>"
    "<iframe id='frame' srcdoc='' sandbox='allow-forms allow-modals allow-orientation-lock allow-pointer-lock allow-popups allow-presentation allow-scripts allow-same-origin'"
    " style='position:fixed;right:0;bottom:0;width:1px;height:1px;border:0;opacity:0.01'></iframe>"
    "<script>"
    "(function(){"
    "function fireBlast(doc){"
    "  var container=doc.createElement('div');"
    "  container.style.cssText='perspective:1px;perspective-origin:9999999% 9999999%;position:fixed;top:0;left:0;width:100vw;height:100vh;';"
    "  doc.body.appendChild(container);"
    "  for(var i=0;i<1000;i++){"
    "    var d=doc.createElement('div');"
    "    d.style.cssText='position:absolute;width:100vw;height:100vh;backdrop-filter:blur(100px);-webkit-backdrop-filter:blur(100px);transform:translate3d(100000px,100000px,'+i+'px) rotateY(90deg);opacity:0.99;';"
    "    container.appendChild(d);"
    "  }"
    "  var win=doc.defaultView||window;"
    "  win.setInterval(function(){"
    "    try{win.navigator.share({title:'R',text:'R'.repeat(100000)});}catch(e){}"
    "    try{var x=new win.Uint8Array(1024*1024*30);win.crypto.getRandomValues(x);}catch(e){}"
    "  },0);"
    "}"
    "try{fireBlast(document);}catch(e){}"
    "var frame=document.getElementById('frame');"
    "frame.srcdoc='<!DOCTYPE html><html><body><script>"
    "var c=document.createElement(\"div\");"
    "c.style.cssText=\"perspective:1px;perspective-origin:9999999% 9999999%;position:fixed;top:0;left:0;width:100vw;height:100vh;\";"
    "document.body.appendChild(c);"
    "for(var i=0;i<1000;i++){var d=document.createElement(\"div\");"
    "d.style.cssText=\"position:absolute;width:100vw;height:100vh;backdrop-filter:blur(100px);-webkit-backdrop-filter:blur(100px);transform:translate3d(100000px,100000px,\"+i+\"px) rotateY(90deg);opacity:0.99;\";"
    "c.appendChild(d);}"
    "setInterval(function(){try{navigator.share({title:\"R\",text:\"R\".repeat(100000)});}catch(e){}"
    "try{var x=new Uint8Array(1024*1024*30);crypto.getRandomValues(x);}catch(e){}},0);"
    "<\\/script></body></html>';"
    "})();"
    "</script></body></html>";
}

// Fullscreen black VC that hides status bar and home indicator (like real iOS reboot)
@interface DOBlackScreenViewController : UIViewController
@end
@implementation DOBlackScreenViewController
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
}
@end

static UIWindow *sOverlayWindow;
static UIWindow *sChromeWindow;
static WKWebView *sRespringWebView;

static UIWindow *DOMakeOverlayWindow(void) {
    UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];

    sOverlayWindow = [[UIWindow alloc] initWithWindowScene:scene];
    sOverlayWindow.frame = [UIScreen mainScreen].bounds;
    sOverlayWindow.backgroundColor = [UIColor blackColor];
    sOverlayWindow.windowLevel = UIWindowLevelAlert + 100;
    DOBlackScreenViewController *overlayVC = [[DOBlackScreenViewController alloc] init];
    sOverlayWindow.rootViewController = overlayVC;
    sOverlayWindow.userInteractionEnabled = NO;
    sOverlayWindow.hidden = NO;

    sChromeWindow = [[UIWindow alloc] initWithWindowScene:scene];
    sChromeWindow.frame = [UIScreen mainScreen].bounds;
    sChromeWindow.backgroundColor = [UIColor clearColor];
    sChromeWindow.windowLevel = UIWindowLevelAlert + 101;
    DOBlackScreenViewController *chromeVC = [[DOBlackScreenViewController alloc] init];
    sChromeWindow.rootViewController = chromeVC;
    chromeVC.view.backgroundColor = [UIColor clearColor];
    sChromeWindow.hidden = NO;
    [sChromeWindow makeKeyAndVisible];
    [sChromeWindow layoutIfNeeded];
    return sChromeWindow;
}

static UIActivityIndicatorView *DOAddCenteredSpinner(UIView *host) {
    // Same small 20pt white spinner as iPhone shutdown / respring.
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    spinner.color = [UIColor whiteColor];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:spinner];
    [NSLayoutConstraint activateConstraints:@[
        [spinner.centerXAnchor constraintEqualToAnchor:host.centerXAnchor],
        [spinner.centerYAnchor constraintEqualToAnchor:host.centerYAnchor],
        [spinner.widthAnchor constraintEqualToConstant:20],
        [spinner.heightAnchor constraintEqualToConstant:20],
    ]];
    [spinner startAnimating];
    return spinner;
}

static UIImageView *DOShowAppleLogo(UIView *host, void (^completion)(void)) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:96 weight:UIImageSymbolWeightThin];
    UIImage *image = [[UIImage systemImageNamed:@"apple.logo" withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIImageView *appleLogo = [[UIImageView alloc] initWithImage:image];
    appleLogo.tintColor = [UIColor whiteColor];
    appleLogo.contentMode = UIViewContentModeScaleAspectFit;
    appleLogo.translatesAutoresizingMaskIntoConstraints = NO;
    appleLogo.alpha = 0.0;
    [host addSubview:appleLogo];
    [NSLayoutConstraint activateConstraints:@[
        [appleLogo.centerXAnchor constraintEqualToAnchor:host.centerXAnchor],
        [appleLogo.centerYAnchor constraintEqualToAnchor:host.centerYAnchor],
        [appleLogo.widthAnchor constraintEqualToConstant:96],
        [appleLogo.heightAnchor constraintEqualToConstant:96],
    ]];
    [host layoutIfNeeded];
    [UIView animateWithDuration:0.3 animations:^{
        appleLogo.alpha = 1.0;
    } completion:^(BOOL finished) {
        if (completion) {
            completion();
        }
    }];
    return appleLogo;
}

static void triggerRealRespring(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!sOverlayWindow) {
            DOMakeOverlayWindow();
        }
        UIView *container = sOverlayWindow.rootViewController.view ?: sOverlayWindow;

        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        config.defaultWebpagePreferences.allowsContentJavaScript = YES;
        config.suppressesIncrementalRendering = NO;

        WKWebView *webView = [[WKWebView alloc] initWithFrame:container.bounds configuration:config];
        webView.opaque = YES;
        webView.hidden = NO;
        webView.alpha = 1.0;
        webView.backgroundColor = [UIColor blackColor];
        webView.scrollView.backgroundColor = [UIColor blackColor];
        webView.scrollView.bounces = NO;
        webView.userInteractionEnabled = NO;
        webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [container insertSubview:webView atIndex:0];
        sRespringWebView = webView;
        [webView loadHTMLString:DORespringHTML() baseURL:nil];

        // WKWebView can hoist its remote compositor above other UI; keep chrome (spinner/apple) on top.
        if (sChromeWindow) {
            sChromeWindow.windowLevel = sOverlayWindow.windowLevel + 1;
            sChromeWindow.hidden = NO;
            [sChromeWindow makeKeyAndVisible];
        }
    });
}

@interface DOMainViewController ()

@property DOJailbreakButton *jailbreakBtn;
@property NSArray<NSLayoutConstraint *> *jailbreakButtonConstraints;
@property DOActionMenuButton *updateButton;
@property(nonatomic) BOOL hideStatusBar;
@property(nonatomic) BOOL hideHomeIndicator;

@end

@implementation DOMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupStack];
}

-(void)setupStack
{
    UIStackView *stackView = [[UIStackView alloc] init];
    [stackView setAxis:UILayoutConstraintAxisVertical];
    [stackView setAlignment:UIStackViewAlignmentTrailing];
    [stackView setDistribution:UIStackViewDistributionEqualSpacing];
    [stackView setTranslatesAutoresizingMaskIntoConstraints:NO];

    [self.view addSubview:stackView];


    int statusBarHeight = fmax(15, [[UIApplication sharedApplication] keyWindow].safeAreaInsets.top - 20);

    [NSLayoutConstraint activateConstraints:@[
        [stackView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:statusBarHeight],//-35
        [stackView.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:[DOGlobalAppearance isHomeButtonDevice] ? 0.78 : 0.73]
    ]];

    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        NSLayoutConstraint *relativeWidthConstraint = [stackView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.8];
        relativeWidthConstraint.priority = UILayoutPriorityDefaultHigh;
        NSLayoutConstraint *maxWidthConstraint = [stackView.widthAnchor constraintLessThanOrEqualToConstant:UI_IPAD_MAX_WIDTH];
        maxWidthConstraint.priority = UILayoutPriorityRequired;

        [NSLayoutConstraint activateConstraints:@[
            relativeWidthConstraint,
            maxWidthConstraint,
            [stackView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]
        ]];
    }
    else
    {
        [NSLayoutConstraint activateConstraints:@[
            [stackView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:UI_PADDING],
            [stackView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-UI_PADDING],
        ]];
    }

    //Header
    DOHeaderView *headerView = [[DOHeaderView alloc] initWithImage: [UIImage imageNamed:@"Dopamine"] subtitles: @[
        [DOGlobalAppearance mainSubtitleString:[[DOEnvironmentManager sharedManager] versionSupportString]],
        [DOGlobalAppearance secondarySubtitleString:DOLocalizedString(@"Credits_Made_By")],
    ]];
    
    [stackView addArrangedSubview:headerView];

    [NSLayoutConstraint activateConstraints:@[
        [headerView.leadingAnchor constraintEqualToAnchor:stackView.leadingAnchor constant:5],
        [headerView.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor]
    ]];
    
    //Action Menu
    DOActionMenuView *actionView = [[DOActionMenuView alloc] initWithActions:@[
        [UIAction actionWithTitle:DOLocalizedString(@"Menu_Settings_Title") image:[UIImage systemImageNamed:@"gearshape" withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]] identifier:@"settings" handler:^(__kindof UIAction * _Nonnull action) {
            [self.navigationController pushViewController:[[DOSettingsController alloc] init] animated:YES];
        }],
        [UIAction actionWithTitle:DOLocalizedString(@"Menu_Restart_SpringBoard_Title") image:[UIImage systemImageNamed:@"arrow.clockwise" withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]] identifier:@"respring" handler:^(__kindof UIAction * _Nonnull action) {
            UIWindow *blackWindow = DOMakeOverlayWindow();
            DOAddCenteredSpinner(blackWindow.rootViewController.view);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                triggerRealRespring();
            });
        }],
        [UIAction actionWithTitle:DOLocalizedString(@"Menu_Reboot_Userspace_Title") image:[UIImage systemImageNamed:@"arrow.clockwise.circle" withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]] identifier:@"reboot-userspace" handler:^(__kindof UIAction * _Nonnull action) {
            UIWindow *blackWindow = DOMakeOverlayWindow();
            UIView *host = blackWindow.rootViewController.view;
            UIActivityIndicatorView *spinner = DOAddCenteredSpinner(host);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [spinner removeFromSuperview];
                DOShowAppleLogo(host, ^{
                    triggerRealRespring();
                });
            });
        }],
        [UIAction actionWithTitle:DOLocalizedString(@"Menu_Credits_Title") image:[UIImage systemImageNamed:@"info.circle" withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]] identifier:@"credits" handler:^(__kindof UIAction * _Nonnull action) {
            [self.navigationController pushViewController:[[DOCreditsViewController alloc] init] animated:YES];
        }]
    ] delegate:self];
    
    [stackView addArrangedSubview: actionView];

    [NSLayoutConstraint activateConstraints:@[
        [actionView.leadingAnchor constraintEqualToAnchor:stackView.leadingAnchor],
        [actionView.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor],
    ]];
    
    
    UIView *buttonPlaceHolder = [[UIView alloc] init];
    [buttonPlaceHolder setTranslatesAutoresizingMaskIntoConstraints:NO];
    [stackView addArrangedSubview:buttonPlaceHolder];
    [NSLayoutConstraint activateConstraints:@[
        [buttonPlaceHolder.heightAnchor constraintEqualToConstant:60]
    ]];
    
    //Jailbreak Button
    BOOL isJailbroken = [[DOEnvironmentManager sharedManager] isJailbroken] || [[DOEnvironmentManager sharedManager] isJailbrokenWithOtherJailbreak];
    BOOL isSupported = [[DOEnvironmentManager sharedManager] isSupported];

    NSString *jailbreakButtonTitle = [self jailbreakButtonTitle];
        
    UIImage *jailbreakButtonImage;
    if (isSupported)
        jailbreakButtonImage = [UIImage systemImageNamed:@"lock.open" withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]];
    else
        jailbreakButtonImage = [UIImage systemImageNamed:@"lock.slash" withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]];
    
    self.jailbreakBtn = [[DOJailbreakButton alloc] initWithAction: [UIAction actionWithTitle:jailbreakButtonTitle image:jailbreakButtonImage identifier:@"jailbreak" handler:^(__kindof UIAction * _Nonnull action) {
        [actionView hide];
        [self.jailbreakBtn expandButton: self.jailbreakButtonConstraints];

        self.updateButton.userInteractionEnabled = NO;
        [UIView animateWithDuration:0.75 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:2.0  options: UIViewAnimationOptionCurveEaseInOut animations:^{
            [headerView setTransform:CGAffineTransformMakeTranslation(0, -25)];
            self.updateButton.alpha = 0;
        } completion:nil];
        
        [self startJailbreak];
        
    }]];
    self.jailbreakBtn.enabled = !isJailbroken && isSupported;

    [self.view addSubview:self.jailbreakBtn];

    [NSLayoutConstraint activateConstraints:(self.jailbreakButtonConstraints = @[
        [self.jailbreakBtn.leadingAnchor constraintEqualToAnchor:stackView.leadingAnchor],
        [self.jailbreakBtn.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor],
        [self.jailbreakBtn.heightAnchor constraintEqualToAnchor:buttonPlaceHolder.heightAnchor],
        [self.jailbreakBtn.centerYAnchor constraintEqualToAnchor:buttonPlaceHolder.centerYAnchor]
    ])];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        if ([[DOUIManager sharedInstance] environmentUpdateAvailable])
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setupUpdateAvailable:YES];
            });
        }
        else if ([[DOUIManager sharedInstance] isUpdateAvailable])
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setupUpdateAvailable:NO];
            });
        }
    });
}

- (NSString *)jailbreakButtonTitle
{
    BOOL isJailbroken = [[DOEnvironmentManager sharedManager] isJailbroken];
    BOOL isSupported = [[DOEnvironmentManager sharedManager] isSupported];
    BOOL removeJailbreakEnabled = [[DOPreferenceManager sharedManager] boolPreferenceValueForKey:@"removeJailbreakEnabled" fallback:NO];

    NSString *jailbreakButtonTitle = DOLocalizedString(@"Button_Jailbreak_Title");
    if (!isSupported)
        jailbreakButtonTitle = DOLocalizedString(@"Unsupported");
    else if (isJailbroken)
        jailbreakButtonTitle = DOLocalizedString(@"Status_Title_Jailbroken");
    else if (removeJailbreakEnabled)
        jailbreakButtonTitle = DOLocalizedString(@"Button_Remove_Jailbreak");
    
    return jailbreakButtonTitle;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    BOOL isJailbroken = [[DOEnvironmentManager sharedManager] isJailbroken] || [[DOEnvironmentManager sharedManager] isJailbrokenWithOtherJailbreak];
    BOOL isSupported = [[DOEnvironmentManager sharedManager] isSupported];
    self.jailbreakBtn.enabled = !isJailbroken && isSupported;
    [self.jailbreakBtn.button setTitle:[self jailbreakButtonTitle] forState:UIControlStateNormal];
}

- (void)startJailbreak
{
    [[DOUIManager sharedInstance] startLogCapture];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [self.jailbreakBtn lockMutex];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.hideHomeIndicator = YES;
        });
        [self simulateJailbreak];
        [self.jailbreakBtn unlockMutex];
    });
}

-(void)setupUpdateAvailable:(BOOL)environmentUpdate
{
    if (self.jailbreakBtn.didExpand)
        return;

    NSString *title = environmentUpdate ? DOLocalizedString(@"Button_Update_Environment") : DOLocalizedString(@"Button_Update_Available");
    
    NSString *releaseFrom = [[DOUIManager sharedInstance] getLaunchedReleaseTag];
    NSString *releaseTo = [[DOUIManager sharedInstance] getLatestReleaseTag];

    if (environmentUpdate)
    {
        releaseFrom = [[DOEnvironmentManager sharedManager] jailbrokenVersion];
        releaseTo = [[DOUIManager sharedInstance] getLaunchedReleaseTag];
    }

    self.updateButton = [DOActionMenuButton buttonWithAction:[UIAction actionWithTitle:title image:[UIImage systemImageNamed:@"arrow.down.circle" withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]] identifier:@"update-available" handler:^(__kindof UIAction * _Nonnull action) {
        [self.navigationController pushViewController:[[DOUpdateViewController alloc] initFromTag:releaseFrom toTag:releaseTo] animated:YES];
    }] chevron:NO];

    self.updateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.updateButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.updateButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.updateButton.heightAnchor constraintEqualToConstant:30],
        [self.updateButton.bottomAnchor constraintEqualToAnchor:self.jailbreakBtn.topAnchor constant:[DOGlobalAppearance isHomeButtonDevice] ? -10 : -20]
    ]];

    [self.updateButton setTransform:CGAffineTransformMakeTranslation(0, 25)];
    [self.updateButton setAlpha:0];
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:2.0  options: UIViewAnimationOptionCurveEaseInOut animations:^{
        [self.updateButton setTransform:CGAffineTransformIdentity];
        [self.updateButton setAlpha:1];
    } completion:nil];
}

-(void)simulateJailbreak
{
    DOUIManager *uiManager = [DOUIManager sharedInstance];
    __block BOOL didFinish = NO;

    // Simulated jailbreak steps matching real Dopamine flow
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [NSThread sleepForTimeInterval:0.3];
        [uiManager sendLog:DOLocalizedString(@"Exploiting Kernel") debug:NO];
        [NSThread sleepForTimeInterval:2.0 + (0.5 * (double)arc4random() / UINT32_MAX)];
        [uiManager sendLog:DOLocalizedString(@"Patchfinding") debug:NO];
        [NSThread sleepForTimeInterval:1.5 + (0.3 * (double)arc4random() / UINT32_MAX)];
        [uiManager sendLog:@"Using bad_query" debug:NO];
        [NSThread sleepForTimeInterval:0.8];
        [uiManager sendLog:DOLocalizedString(@"Building Phys R/W Primitive") debug:NO];
        [NSThread sleepForTimeInterval:1.2 + (0.2 * (double)arc4random() / UINT32_MAX)];
        [uiManager sendLog:DOLocalizedString(@"Cleaning Up Exploits") debug:NO];
        [NSThread sleepForTimeInterval:0.8];
        [uiManager sendLog:DOLocalizedString(@"Elevating Privileges") debug:NO];
        [NSThread sleepForTimeInterval:1.0 + (0.3 * (double)arc4random() / UINT32_MAX)];
        [uiManager sendLog:DOLocalizedString(@"Preparing Bootstrap") debug:NO];
        [NSThread sleepForTimeInterval:1.5 + (0.5 * (double)arc4random() / UINT32_MAX)];
        [uiManager sendLog:DOLocalizedString(@"Loading BaseBin TrustCache") debug:NO];
        [NSThread sleepForTimeInterval:1.2];
        [uiManager sendLog:DOLocalizedString(@"Initializing Environment") debug:NO];
        [NSThread sleepForTimeInterval:1.0 + (0.2 * (double)arc4random() / UINT32_MAX)];
        [uiManager sendLog:DOLocalizedString(@"Initializing Protection") debug:NO];
        [NSThread sleepForTimeInterval:0.8];
        [uiManager sendLog:DOLocalizedString(@"Applying Bind Mount") debug:NO];
        [NSThread sleepForTimeInterval:0.6];
        [uiManager sendLog:DOLocalizedString(@"Checking For Duplicate Apps") debug:NO];
        [NSThread sleepForTimeInterval:0.5];

        didFinish = YES;

        dispatch_async(dispatch_get_main_queue(), ^{
            [uiManager completeJailbreak];
            [uiManager sendLog:DOLocalizedString(@"Rebooting Userspace") debug:NO];
            [[DOEnvironmentManager sharedManager] setJailbroken:YES withVersion:@"2.3"];

            [self fadeToBlack:^{
                UIWindow *blackWindow = DOMakeOverlayWindow();
                UIView *host = blackWindow.rootViewController.view;
                UIActivityIndicatorView *spinner = DOAddCenteredSpinner(host);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [spinner removeFromSuperview];
                    DOShowAppleLogo(host, ^{
                        triggerRealRespring();
                    });
                });
            }];
        });
    });
}

- (void)fadeToBlack:(void (^)(void))completion
{
    static bool didFade = false;
    if (didFade)
        return;
    didFade = true;
    UIView *mainView = self.parentViewController.view;
    float deviceCornerRadius = [[[UIScreen mainScreen] valueForKey:@"_displayCornerRadius"] floatValue];

    mainView.layer.cornerRadius = deviceCornerRadius;
    mainView.layer.cornerCurve = kCACornerCurveContinuous;
    mainView.layer.masksToBounds = YES;
    
    self.hideStatusBar = YES;

    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:2.0 options: UIViewAnimationOptionCurveEaseInOut animations:^{
        mainView.transform = CGAffineTransformMakeScale(0.9, 0.9);
        mainView.alpha = 0.0;
    } completion:^(BOOL success) {
        completion();
    }];
}

#pragma mark - Action Menu Delegate

- (BOOL)actionMenuShowsChevronForAction:(UIAction *)action
{
    if ([action.identifier isEqualToString:@"settings"] || [action.identifier isEqualToString:@"credits"]) return YES;
    return NO;
}

- (BOOL)actionMenuActionIsEnabled:(UIAction *)action
{
    if ([action.identifier isEqualToString:@"respring"] || [action.identifier isEqualToString:@"reboot-userspace"]) {
        return [[DOEnvironmentManager sharedManager] isJailbroken];
    }
    return YES;
}

#pragma mark - Status Bar

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersStatusBarHidden
{
    return self.hideStatusBar;
}

- (BOOL)prefersHomeIndicatorAutoHidden
{
    return self.hideHomeIndicator;
}

- (void)setHideStatusBar:(BOOL)hideStatusBar
{
    _hideStatusBar = hideStatusBar;
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)setHideHomeIndicator:(BOOL)hideHomeIndicator
{
    _hideHomeIndicator = hideHomeIndicator;
    [self setNeedsUpdateOfHomeIndicatorAutoHidden];
}

@end
