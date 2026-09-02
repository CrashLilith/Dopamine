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
            // Simulate respring: black screen with spinner, then fade back
            UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
            UIWindow *blackWindow = [[UIWindow alloc] initWithWindowScene:scene];
            blackWindow.frame = [UIScreen mainScreen].bounds;
            blackWindow.backgroundColor = [UIColor blackColor];
            blackWindow.windowLevel = UIWindowLevelAlert + 100;
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
            spinner.color = [UIColor whiteColor];
            spinner.center = CGPointMake(blackWindow.bounds.size.width / 2, blackWindow.bounds.size.height / 2);
            [spinner startAnimating];
            [blackWindow addSubview:spinner];
            blackWindow.hidden = NO;
            [blackWindow makeKeyAndVisible];
            // After 5s, fade back to app (like SpringBoard finished reloading)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.4 animations:^{
                    blackWindow.alpha = 0.0;
                } completion:^(BOOL finished) {
                    blackWindow.hidden = YES;
                    [blackWindow resignKeyWindow];
                }];
            });
        }],
        [UIAction actionWithTitle:DOLocalizedString(@"Menu_Reboot_Userspace_Title") image:[UIImage systemImageNamed:@"arrow.clockwise.circle" withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]] identifier:@"reboot-userspace" handler:^(__kindof UIAction * _Nonnull action) {
            // Simulate userspace reboot: black + spinner, then Apple logo, then fade back
            UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
            UIWindow *blackWindow = [[UIWindow alloc] initWithWindowScene:scene];
            blackWindow.frame = [UIScreen mainScreen].bounds;
            blackWindow.backgroundColor = [UIColor blackColor];
            blackWindow.windowLevel = UIWindowLevelAlert + 100;

            // Spinner phase
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
            spinner.color = [UIColor whiteColor];
            spinner.center = CGPointMake(blackWindow.bounds.size.width / 2, blackWindow.bounds.size.height / 2);
            [spinner startAnimating];
            [blackWindow addSubview:spinner];

            blackWindow.hidden = NO;
            [blackWindow makeKeyAndVisible];

            // After 4s: remove spinner, show Apple logo
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [spinner removeFromSuperview];

                UIImageView *appleLogo = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"apple.logo" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:60 weight:UIImageSymbolWeightThin]]];
                appleLogo.tintColor = [UIColor whiteColor];
                appleLogo.center = CGPointMake(blackWindow.bounds.size.width / 2, blackWindow.bounds.size.height / 2);
                appleLogo.alpha = 0.0;
                [blackWindow addSubview:appleLogo];

                [UIView animateWithDuration:0.3 animations:^{
                    appleLogo.alpha = 1.0;
                }];

                // After 4s more: fade everything away
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [UIView animateWithDuration:0.5 animations:^{
                        blackWindow.alpha = 0.0;
                    } completion:^(BOOL finished) {
                        blackWindow.hidden = YES;
                        [blackWindow resignKeyWindow];
                    }];
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

            // Simulate userspace reboot animation after jailbreak
            [self fadeToBlack:^{
                // Once faded, overlay full black window with spinner + Apple logo sequence
                UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
                UIWindow *blackWindow = [[UIWindow alloc] initWithWindowScene:scene];
                blackWindow.frame = [UIScreen mainScreen].bounds;
                blackWindow.backgroundColor = [UIColor blackColor];
                blackWindow.windowLevel = UIWindowLevelAlert + 100;

                UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
                spinner.color = [UIColor whiteColor];
                spinner.center = CGPointMake(blackWindow.bounds.size.width / 2, blackWindow.bounds.size.height / 2);
                [spinner startAnimating];
                [blackWindow addSubview:spinner];

                blackWindow.hidden = NO;
                [blackWindow makeKeyAndVisible];

                // After 4s: remove spinner, show Apple logo
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [spinner removeFromSuperview];

                    UIImageView *appleLogo = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"apple.logo" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:60 weight:UIImageSymbolWeightThin]]];
                    appleLogo.tintColor = [UIColor whiteColor];
                    appleLogo.center = CGPointMake(blackWindow.bounds.size.width / 2, blackWindow.bounds.size.height / 2);
                    appleLogo.alpha = 0.0;
                    [blackWindow addSubview:appleLogo];

                    [UIView animateWithDuration:0.3 animations:^{
                        appleLogo.alpha = 1.0;
                    }];

                    // After 4s more: fade out and show app with "Jailbroken" state
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [UIView animateWithDuration:0.5 animations:^{
                            blackWindow.alpha = 0.0;
                        } completion:^(BOOL finished) {
                            blackWindow.hidden = YES;
                            [blackWindow resignKeyWindow];
                            // Reload button title to show "Jailbroken"
                            [self.jailbreakBtn.button setTitle:[self jailbreakButtonTitle] forState:UIControlStateNormal];
                            self.jailbreakBtn.enabled = NO;
                        }];
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
