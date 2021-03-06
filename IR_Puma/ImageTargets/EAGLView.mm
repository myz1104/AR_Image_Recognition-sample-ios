/*==============================================================================
Copyright (c) 2010-2011 QUALCOMM Austria Research Center GmbH.
All Rights Reserved.
Qualcomm Confidential and Proprietary
==============================================================================*/


#import <QuartzCore/QuartzCore.h>
#import "EAGLView.h"
#import <QCAR/QCAR.h>
#import <QCAR/CameraDevice.h>
#import <QCAR/Tracker.h>
#import <QCAR/VideoBackgroundConfig.h>
#import <QCAR/Renderer.h>
#import <QCAR/Tool.h>
#import <QCAR/Trackable.h>
#import <AVFoundation/AVFoundation.h>
#import <tgmath.h>

#import "ImageTargetsAppDelegate.h"



#ifndef USE_OPENGL1
#import "ShaderUtils.h"
#define MAKESTRING(x) #x
#endif

#define width_height_treshhold 800

namespace {
    // Model scale factor
    const float kObjectScale = 3.0f;
    
}


@interface EAGLView (PrivateMethods)
- (void)setFramebuffer;
- (BOOL)presentFramebuffer;
- (void)createFramebuffer;
- (void)deleteFramebuffer;
- (int)loadTextures;
- (void)updateApplicationStatus:(status)newStatus;
- (void)bumpAppStatus;
- (void)initApplication;
- (void)initQCAR;
- (void)initApplicationAR;
- (void)loadTracker;
- (void)startCamera;
- (void)stopCamera;
- (void)configureVideoBackground;
- (void)initRendering;
@end


@implementation EAGLView






// You must implement this method
+ (Class)layerClass
{
    return [CAEAGLLayer class];
}


- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    
	if (self) {
        CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
        
        eaglLayer.opaque = TRUE;
        eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSNumber numberWithBool:FALSE], kEAGLDrawablePropertyRetainedBacking,
                                        kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat,
                                        nil];
        
#ifdef USE_OPENGL1
        context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
        ARData.QCARFlags = QCAR::GL_11;
#else
        context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        ARData.QCARFlags = QCAR::GL_20;
#endif
        
        NSLog(@"QCAR OpenGL flag: %d", ARData.QCARFlags);
        
        if (!context) {
            NSLog(@"Failed to create ES context");
        }
    }
    
    return self;
}

- (void)dealloc
{
    [self deleteFramebuffer];
    
    // Tear down context
    if ([EAGLContext currentContext] == context) {
        [EAGLContext setCurrentContext:nil];
    }
    
    [context release];
    [super dealloc];
}

- (void)createFramebuffer
{
#ifdef USE_OPENGL1
    if (context && !defaultFramebuffer) {
        [EAGLContext setCurrentContext:context];
        
        // Create default framebuffer object
        glGenFramebuffersOES(1, &defaultFramebuffer);
        glBindFramebufferOES(GL_FRAMEBUFFER_OES, defaultFramebuffer);
        
        // Create colour renderbuffer and allocate backing store
        glGenRenderbuffersOES(1, &colorRenderbuffer);
        glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorRenderbuffer);
        
        // Allocate the renderbuffer's storage (shared with the drawable object)
        [context renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:(CAEAGLLayer*)self.layer];
        glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &framebufferWidth);
        glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &framebufferHeight);
        
        // Create the depth render buffer and allocate storage
        glGenRenderbuffersOES(1, &depthRenderbuffer);
        glBindRenderbufferOES(GL_RENDERBUFFER_OES, depthRenderbuffer);
        glRenderbufferStorageOES(GL_RENDERBUFFER_OES, GL_DEPTH_COMPONENT16_OES, framebufferWidth, framebufferHeight);
        
        // Attach colour and depth render buffers to the frame buffer
        glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, colorRenderbuffer);
        glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_DEPTH_ATTACHMENT_OES, GL_RENDERBUFFER_OES, depthRenderbuffer);
        
        // Leave the colour render buffer bound so future rendering operations will act on it
        glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorRenderbuffer);
    }
#else
    if (context && !defaultFramebuffer) {
        [EAGLContext setCurrentContext:context];
        
        // Create default framebuffer object
        glGenFramebuffers(1, &defaultFramebuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
        
        // Create colour render buffer and allocate backing store
        glGenRenderbuffers(1, &colorRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);

        // Allocate the renderbuffer's storage (shared with the drawable object)
        [context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &framebufferWidth);
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &framebufferHeight);
        
        // Create the depth render buffer and allocate storage
        glGenRenderbuffers(1, &depthRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, depthRenderbuffer);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, framebufferWidth, framebufferHeight);
        
        // Attach colour and depth render buffers to the frame buffer
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorRenderbuffer);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderbuffer);
        
        // Leave the colour render buffer bound so future rendering operations will act on it
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
        
        if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
            NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
        }
    }
#endif
}

- (void)deleteFramebuffer
{
    if (context) {
        [EAGLContext setCurrentContext:context];
        
#ifdef USE_OPENGL1
        if (defaultFramebuffer) {
            glDeleteFramebuffersOES(1, &defaultFramebuffer);
            defaultFramebuffer = 0;
        }
        
        if (colorRenderbuffer) {
            glDeleteRenderbuffersOES(1, &colorRenderbuffer);
            colorRenderbuffer = 0;
        }
        
        if (depthRenderbuffer) {
            glDeleteRenderbuffersOES(1, &depthRenderbuffer);
            depthRenderbuffer = 0;
        }
#else
        if (defaultFramebuffer) {
            glDeleteFramebuffers(1, &defaultFramebuffer);
            defaultFramebuffer = 0;
        }
        
        if (colorRenderbuffer) {
            glDeleteRenderbuffers(1, &colorRenderbuffer);
            colorRenderbuffer = 0;
        }
        
        if (depthRenderbuffer) {
            glDeleteRenderbuffers(1, &depthRenderbuffer);
            depthRenderbuffer = 0;
        }
#endif
    }
}

- (void)setFramebuffer
{
    //videoPlaying = NO;
    if (context) {
        [EAGLContext setCurrentContext:context];
        
        if (!defaultFramebuffer) {
            // Perform on the main thread to ensure safe memory allocation for
            // the shared buffer.  Block until the operation is complete to
            // prevent simultaneous access to the OpenGL context
            [self performSelectorOnMainThread:@selector(createFramebuffer) withObject:self waitUntilDone:YES];
        }
        
#ifdef USE_OPENGL1
        glBindFramebufferOES(GL_FRAMEBUFFER_OES, defaultFramebuffer);
#else
        glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
#endif
    }
}

- (BOOL)presentFramebuffer
{
    BOOL success = FALSE;
    
    if (context) {
        [EAGLContext setCurrentContext:context];
        
#ifdef USE_OPENGL1
        glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorRenderbuffer);
#else
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
#endif
        
        success = [context presentRenderbuffer:GL_RENDERBUFFER];
    }
    
    return success;
}

- (void)layoutSubviews
{
    // The framebuffer will be re-created at the beginning of the next
    // setFramebuffer method call.
    [self deleteFramebuffer];
}


////////////////////////////////////////////////////////////////////////////////
- (void)onCreate
{
    NSLog(@"EAGLView onCreate()");
    ARData.appStatus = APPSTATUS_UNINITED;
    
    /*// Load textures
    int nErr = [self loadTextures];
    
    if (noErr == nErr) {
        [self updateApplicationStatus:APPSTATUS_INIT_APP];
    }*/
    
     [self updateApplicationStatus:APPSTATUS_INIT_APP];
}


////////////////////////////////////////////////////////////////////////////////
- (void)onDestroy
{
    NSLog(@"EAGLView onDestroy()");
    // Release the textures array
    [ARData.textures release];
    
    // Deinitialise QCAR SDK
    QCAR::deinit();
}


////////////////////////////////////////////////////////////////////////////////
- (void)onResume
{
    NSLog(@"EAGLView onResume()");
    
    // If the app status is APPSTATUS_CAMERA_STOPPED, QCAR must have been fully
    // initialised
    if (APPSTATUS_CAMERA_STOPPED == ARData.appStatus) {
        // QCAR-specific resume operation
        QCAR::onResume();
        
        [self updateApplicationStatus:APPSTATUS_CAMERA_RUNNING];
    }
}


////////////////////////////////////////////////////////////////////////////////
- (void)onPause
{
    NSLog(@"EAGLView onPause()");
    
    // If the app status is APPSTATUS_CAMERA_RUNNING, QCAR must have been fully
    // initialised
    if (APPSTATUS_CAMERA_RUNNING == ARData.appStatus) {
        [self updateApplicationStatus:APPSTATUS_CAMERA_STOPPED];
        
        // QCAR-specific pause operation
        QCAR::onPause();
    }
}

////////////////////////////////////////////////////////////////////////////////
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    exit(0);
}

////////////////////////////////////////////////////////////////////////////////
- (void)updateApplicationStatus:(status)newStatus
{
    if (newStatus != ARData.appStatus && APPSTATUS_ERROR != ARData.appStatus) {
        ARData.appStatus = newStatus;
        
        switch (ARData.appStatus) {
            case APPSTATUS_INIT_APP:
                // Initialise the application
                [self initApplication];
                [self updateApplicationStatus:APPSTATUS_INIT_QCAR];
                break;
                
            case APPSTATUS_INIT_QCAR:
                // Initialise QCAR
                [self performSelectorInBackground:@selector(initQCAR) withObject:nil];
                break;
                
            case APPSTATUS_INIT_APP_AR:
                // AR-specific initialisation
                [self initApplicationAR];
                [self updateApplicationStatus:APPSTATUS_INIT_TRACKER];
                break;
                
            case APPSTATUS_INIT_TRACKER:
                // Load tracker data
                [self performSelectorInBackground:@selector(loadTracker) withObject:nil];
                break;
                
            case APPSTATUS_INITED:
                // These two calls to setHint tell QCAR to split work over
                // multiple frames.  Depending on your requirements you can opt
                // to omit these.
                QCAR::setHint(QCAR::HINT_IMAGE_TARGET_MULTI_FRAME_ENABLED, 1);
                QCAR::setHint(QCAR::HINT_IMAGE_TARGET_MILLISECONDS_PER_MULTI_FRAME, 25);
                
                // Here we could also make a QCAR::setHint call to set the
                // maximum number of simultaneous targets                
                // QCAR::setHint(QCAR::HINT_MAX_SIMULTANEOUS_IMAGE_TARGETS, 2);
                
                // Initialisation is complete, start QCAR
                QCAR::onResume();
                
                [self updateApplicationStatus:APPSTATUS_CAMERA_RUNNING];
                break;
                
            case APPSTATUS_CAMERA_RUNNING:
                [self startCamera];
                break;
                
            case APPSTATUS_CAMERA_STOPPED:
                [self stopCamera];
                break;
                
            default:
                NSLog(@"updateApplicationStatus: invalid app status");
                break;
        }
    }
    
    if (APPSTATUS_ERROR == ARData.appStatus) {
        // Application initialisation failed, display an alert view
        UIAlertView* alert;
        const char *msgNetwork = "Network connection required to initialize camera "
        "settings. Please check your connection and restart the application.";
        const char *msgDevice = "Failed to initialize QCAR because this device is not supported.";
        const char *msgDefault = "Application initialisation failed.";
        const char *msg = msgDefault;
        
        switch (ARData.errorCode) {
            case QCAR::INIT_CANNOT_DOWNLOAD_DEVICE_SETTINGS:
                msg = msgNetwork;
                break;
            case QCAR::INIT_DEVICE_NOT_SUPPORTED:
                msg = msgDevice;
                break;
            case QCAR::INIT_ERROR:
            default:
                break;
        }
        
        alert = [[UIAlertView alloc] initWithTitle:@"Error" message:[NSString stringWithUTF8String:msg] delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alert show];
        [alert release];
    }
}


////////////////////////////////////////////////////////////////////////////////
// Bump the application status on one step
- (void)bumpAppStatus
{
    [self updateApplicationStatus:(status)(ARData.appStatus + 1)];
}


////////////////////////////////////////////////////////////////////////////////
// Initialise the application
- (void)initApplication
{
    // Get the device screen dimensions
    ARData.screenRect = [[UIScreen mainScreen] bounds];
    
    // Inform QCAR that the drawing surface has been created
    QCAR::onSurfaceCreated();
    
    // Inform QCAR that the drawing surface size has changed
    QCAR::onSurfaceChanged(ARData.screenRect.size.height, ARData.screenRect.size.width);
}


////////////////////////////////////////////////////////////////////////////////
// Initialise QCAR [performed on a background thread]
- (void)initQCAR
{
    currentClip = 1;
    
    // Background thread must have its own autorelease pool
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    QCAR::setInitParameters(ARData.QCARFlags);
    
    int nPercentComplete = 0;
    
    do {
        nPercentComplete = QCAR::init();
    } while (0 <= nPercentComplete && 100 > nPercentComplete);
    
    NSLog(@"QCAR::init percent: %d", nPercentComplete);
    
    if (0 > nPercentComplete) {
        ARData.appStatus = APPSTATUS_ERROR;
        ARData.errorCode = nPercentComplete;
    }    
    
    // Continue execution on the main thread
    [self performSelectorOnMainThread:@selector(bumpAppStatus) withObject:nil waitUntilDone:NO];
    
    [pool release];    
} 


////////////////////////////////////////////////////////////////////////////////
// Initialise the AR parts of the application
- (void)initApplicationAR
{
    // Initialise rendering
    [self initRendering];
}


////////////////////////////////////////////////////////////////////////////////
// Load the tracker data [performed on a background thread]
- (void)loadTracker
{
    int nPercentComplete = 0;

    // Background thread must have its own autorelease pool
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    
    // Load the tracker data
    do {
        nPercentComplete = QCAR::Tracker::getInstance().load();
    } while (0 <= nPercentComplete && 100 > nPercentComplete);

    if (0 > nPercentComplete) {
        ARData.appStatus = APPSTATUS_ERROR;
        ARData.errorCode = nPercentComplete;
    }
    
    // Continue execution on the main thread
    [self performSelectorOnMainThread:@selector(bumpAppStatus) withObject:nil waitUntilDone:NO];
    
    [pool release];
}


////////////////////////////////////////////////////////////////////////////////
// Start capturing images from the camera
- (void)startCamera
{
    // Initialise the camera
    if (QCAR::CameraDevice::getInstance().init()) {
        // Configure video background
        [self configureVideoBackground];
        
        // Select the default mode
        if (QCAR::CameraDevice::getInstance().selectVideoMode(QCAR::CameraDevice::MODE_DEFAULT)) {
            // Start camera capturing
            if (QCAR::CameraDevice::getInstance().start()) {
                // Start the tracker
                QCAR::Tracker::getInstance().start();
                
                // Cache the projection matrix
                const QCAR::CameraCalibration& cameraCalibration = QCAR::Tracker::getInstance().getCameraCalibration();
                projectionMatrix = QCAR::Tool::getProjectionGL(cameraCalibration, 2.0f, 2000.0f);
            }
        }
    }
}


////////////////////////////////////////////////////////////////////////////////
// Stop capturing images from the camera
- (void)stopCamera
{
    QCAR::Tracker::getInstance().stop();
    QCAR::CameraDevice::getInstance().stop();
    QCAR::CameraDevice::getInstance().deinit();
}


////////////////////////////////////////////////////////////////////////////////
// Configure the video background
- (void)configureVideoBackground
{
    // Get the default video mode
    QCAR::CameraDevice& cameraDevice = QCAR::CameraDevice::getInstance();
    QCAR::VideoMode videoMode = cameraDevice.getVideoMode(QCAR::CameraDevice::MODE_DEFAULT);
    
    // Configure the video background
    QCAR::VideoBackgroundConfig config;
    config.mEnabled = true;
    config.mSynchronous = true;
    config.mPosition.data[0] = 0.0f;
    config.mPosition.data[1] = 0.0f;
    
    // Compare aspect ratios of video and screen.  If they are different
    // we use the full screen size while maintaining the video's aspect
    // ratio, which naturally entails some cropping of the video.
    // Note - screenRect is portrait but videoMode is always landscape,
    // which is why "width" and "height" appear to be reversed.
    float arVideo = (float)videoMode.mWidth / (float)videoMode.mHeight;
    float arScreen = ARData.screenRect.size.height / ARData.screenRect.size.width;
    
    if (arVideo > arScreen)
    {
        // Video mode is wider than the screen.  We'll crop the left and right edges of the video
        config.mSize.data[0] = (int)ARData.screenRect.size.width * arVideo;
        config.mSize.data[1] = (int)ARData.screenRect.size.width;
    }
    else
    {
        // Video mode is taller than the screen.  We'll crop the top and bottom edges of the video.
        // Also used when aspect ratios match (no cropping).
        config.mSize.data[0] = (int)ARData.screenRect.size.height;
        config.mSize.data[1] = (int)ARData.screenRect.size.height / arVideo;
    }
    
    // Set the config
    QCAR::Renderer::getInstance().setVideoBackgroundConfig(config);
}


////////////////////////////////////////////////////////////////////////////////
// Initialise OpenGL rendering
- (void)initRendering
{
    /*// Define the clear colour
    glClearColor(0.0f, 0.0f, 0.0f, QCAR::requiresAlpha() ? 0.0f : 1.0f);
    
    // Generate the OpenGL texture objects
    for (int i = 0; i < [ARData.textures count]; ++i) {
        GLuint nID;
        Texture* texture = [ARData.textures objectAtIndex:i];
        glGenTextures(1, &nID);
        [texture setTextureID: nID];
        glBindTexture(GL_TEXTURE_2D, nID);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, [texture width], [texture height], 0, GL_RGBA, GL_UNSIGNED_BYTE, (GLvoid*)[texture pngData]);
    }
    
#ifndef USE_OPENGL1
    if (QCAR::GL_20 & ARData.QCARFlags) {
        // OpenGL 2 initialisation
        shaderProgramID = ShaderUtils::createProgramFromBuffer(vertexShader, fragmentShader);
        vertexHandle = glGetAttribLocation(shaderProgramID, "vertexPosition");
        normalHandle = glGetAttribLocation(shaderProgramID, "vertexNormal");
        textureCoordHandle = glGetAttribLocation(shaderProgramID, "vertexTexCoord");
        mvpMatrixHandle = glGetUniformLocation(shaderProgramID, "modelViewProjectionMatrix");
    }
#endif*/
}


- (CGPoint) projectCoord:(CGPoint)coord inView:(const QCAR::CameraCalibration&)cameraCalibration andPose:(QCAR::Matrix34F)pose withOffset:(CGPoint)offset
{
    CGPoint converted;
    
    QCAR::Vec3F vec(coord.x,coord.y,0);
    QCAR::Vec2F sc = QCAR::Tool::projectPoint(cameraCalibration, pose, vec);
    converted.x = sc.data[0] - offset.x;
    converted.y = sc.data[1] - offset.y;
    
    return converted;
}

- (void) calcScreenCoordsOf:(CGSize)target inView:(CGFloat *)matrix inPose:(QCAR::Matrix34F)pose
{
    // 0,0 is at centre of target so extremities are at w/2,h/2
    CGFloat w = target.width/2;
    CGFloat h = target.height/2;
    
    const QCAR::Tracker& tracker = QCAR::Tracker::getInstance();
    const QCAR::CameraCalibration& cameraCalibration = tracker.getCameraCalibration();
    
    // calculate any mismatch of screen to video size
    QCAR::CameraDevice& cameraDevice = QCAR::CameraDevice::getInstance();
    QCAR::VideoMode videoMode = cameraDevice.getVideoMode(QCAR::CameraDevice::MODE_DEFAULT);
    CGPoint margin = {(videoMode.mWidth - self.frame.size.width)/2, (videoMode.mHeight - self.frame.size.height)/2};
    
    // now project the 4 corners of the target
    s0 = [self projectCoord:CGPointMake(-w,h) inView:cameraCalibration andPose:pose withOffset:margin];
    s1 = [self projectCoord:CGPointMake(-w,-h) inView:cameraCalibration andPose:pose withOffset:margin];
    s2 = [self projectCoord:CGPointMake(w,-h) inView:cameraCalibration andPose:pose withOffset:margin];
    s3 = [self projectCoord:CGPointMake(w,h) inView:cameraCalibration andPose:pose withOffset:margin];
}

-(CGFloat)maxInArray:(float[])array count:(int)n
{
    CGFloat max;
    max = array[n];
    for(int c=0; c<n; c++)
    {
        if (array[c]>max) {
            max = array[c];
        }        
    }
    return max;
}

-(CGFloat)minInArray:(float[])array count:(int)n
{
    CGFloat min;
    min = array[0];
    for(int c=0; c<n; c++)
    {
        if (array[c]<min) {
            min = array[c];
        }        
    }
    return min;
}


////////////////////////////////////////////////////////////////////////////////
// Draw the current frame using OpenGL
//
// This method is called by QCAR when it wishes to render the current frame to
// the screen.
//
// *** QCAR will call this method on a single background thread ***


- (void)renderFrameQCAR
{
    [self setFramebuffer];
    
    CGSize target;

    QCAR::State state = QCAR::Renderer::getInstance().begin();
    
    if (state.getNumActiveTrackables() == 0) {
        if(trash > 25)
        {
            videoPlaying = NO;   
            [self performSelectorOnMainThread:@selector(closeMovieController) withObject:nil waitUntilDone:NO]; 
            trash = 0;                        
        }
        else
            trash++;  
     
        
    // Scan detect
    }else
        for (int i = 0; i < state.getNumActiveTrackables(); ++i)       
        {            
            const QCAR::Trackable* trackable = state.getActiveTrackable(i);             
            if(strcmp(trackable->getName(),"shoes_2"))   
            {
                target = CGSizeMake(400, 298);    
                if (currentClip != 1) 
                {
                    [((ImageTargetsAppDelegate *)[[UIApplication sharedApplication] delegate]) changeUrl:@"clip1_"];
                    [self performSelectorOnMainThread:@selector(changeContentOfMoview) withObject:nil waitUntilDone:NO];
                    currentClip = 1;                   
                }
            }           
            else 
            {                               
                target =  CGSizeMake(331, 492); 
                if (currentClip != 2) {
                    [((ImageTargetsAppDelegate *)[[UIApplication sharedApplication] delegate]) changeUrl:@"clip2_"];
                    [self performSelectorOnMainThread:@selector(changeContentOfMoview) withObject:nil waitUntilDone:NO];
                    currentClip = 2;
                }                
            }                 

            
            QCAR::Matrix44F modelViewProjection;        
            QCAR::Matrix44F modelViewMatrix = QCAR::Tool::convertPose2GLMatrix(trackable->getPose());        
            
            ShaderUtils::translatePoseMatrix(0.0f, 0.0f, kObjectScale, &modelViewMatrix.data[0]);
            ShaderUtils::scalePoseMatrix(kObjectScale, kObjectScale, kObjectScale, &modelViewMatrix.data[0]);
            ShaderUtils::multiplyMatrix(&projectionMatrix.data[0], &modelViewMatrix.data[0], &modelViewProjection.data[0]); 
            
            [self calcScreenCoordsOf:target inView:&modelViewProjection.data[0] inPose:trackable->getPose()];
            
            float ar1[] = {s0.x, s1.x, s2.x, s3.x};
            float ar2[] = {s0.y, s1.y, s2.y, s3.y};
            
            CGFloat x = [self minInArray:ar1 count:4];
            CGFloat width = [self maxInArray:ar1 count:4] - x;
            
            CGFloat y = [self minInArray:ar2 count:4];
            CGFloat height = [self maxInArray:ar2 count:4] - y;
            
            center = CGPointMake(x, y);
               
            if (fabsf(subScreenBounds.size.width * subScreenBounds.size.height - width*height) > width_height_treshhold) {                
                scaleKoeffs = (width*height);
                subScreenBounds =  CGRectMake(x,y,width,height);                
            } 
                
            if (!videoPlaying)
            {
                [self performSelectorOnMainThread:@selector(showMovieController) withObject:nil waitUntilDone:NO];
                videoPlaying = YES;
            }  
            else
                [self performSelectorInBackground:@selector(changeBoundsOfMoview) withObject:nil];               
        }
    [self presentFramebuffer];
}
    
- (void)showMovieController
{
    ((ImageTargetsAppDelegate *)[[UIApplication sharedApplication] delegate]).mon.view.hidden = NO;
    [((ImageTargetsAppDelegate *)[[UIApplication sharedApplication] delegate]).mon startAnimating];    
 
}

- (void)closeMovieController
{
//    ((ImageTargetsAppDelegate *)[[UIApplication sharedApplication] delegate]).mon.view.hidden = YES;
    [((ImageTargetsAppDelegate *)[[UIApplication sharedApplication] delegate]).mon stopAnimating];
}
    
-(void)changeBoundsOfMoview
{
     NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    
    CGFloat tmp;   
    CGRect temp ;
    
    if (currentClip == 1) {
                tmp = scaleKoeffs*3/(playerWidth*playerHeight);
        temp = CGRectMake(center.x, center.y, playerWidth*tmp, playerHeight*tmp); 
 
    }
    else
    {
                tmp = scaleKoeffs*4/(playerWidth*playerHeight); 
        temp = CGRectMake(center.x, center.y, playerWidth*tmp, playerHeight*tmp); 
   
    }
    
     
//    [((ImageTargetsAppDelegate *)[[UIApplication sharedApplication] delegate]).mon.imageView setFrame:temp];
     [((ImageTargetsAppDelegate *)[[UIApplication sharedApplication] delegate]).mon.player.view setFrame:temp];
    [pool release];
}

-(void)changeContentOfMoview
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    [((ImageTargetsAppDelegate *)[[UIApplication sharedApplication] delegate]).mon reload];
    [pool release];

}

@end
