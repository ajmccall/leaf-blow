//
//  HelloWorldLayer.mm
//  WordPress
//
//  Created by Alasdair McCall on 11/11/2012.
//  Copyright __MyCompanyName__ 2012. All rights reserved.
//

// Import the interfaces
#import "HelloWorldLayer.h"
#import "AppDelegate.h"
#import "PhysicsSprite.h"
#import <AVFoundation/AVFoundation.h>

#pragma mark - HelloWorldLayer

@interface HelloWorldLayer() {
    AVAudioRecorder *recorder;
    NSTimer *levelTimer;
    double lowPassResults;
}

-(void)levelTimerCallback:(NSTimer *)timer;
-(void) initPhysics;
@end

@implementation HelloWorldLayer

+(CCScene *) scene{
	// 'scene' is an autorelease object.
	CCScene *scene = [CCScene node];
	
	// 'layer' is an autorelease object.
	HelloWorldLayer *layer = [HelloWorldLayer node];
	
	// add layer as a child to scene
	[scene addChild: layer];
	
	// return the scene
	return scene;
}

-(void) addLeaf {
    
    NSString *leafFileName = [NSString stringWithFormat:@"leaf%dx100.png",1 + arc4random() % 2];
    CGSize winSize = [[CCDirector sharedDirector] winSize];
    CGPoint pos = CGPointMake(arc4random() % (int) winSize.width, arc4random() % (int) winSize.height);
    
    //create a sprite
    PhysicsSprite *sprite = [PhysicsSprite spriteWithFile:leafFileName];
    [self addChild:sprite];
    CGSize imageSize = [UIImage imageNamed:leafFileName].size;
    
	// Define the sprite body.
	b2BodyDef bodyDef;
	bodyDef.type = b2_dynamicBody;
	bodyDef.position.Set(pos.x/PTM_RATIO, pos.y/PTM_RATIO);
	b2Body *body = world->CreateBody(&bodyDef);
    
    //creat sprite shape
    CGFloat radius = imageSize.width < imageSize.height ? imageSize.width/2 : imageSize.height/2;
    b2CircleShape circle;
    circle.m_radius = radius/PTM_RATIO * (2.0f/3.0f);
    
    //create sprite fixture
    b2FixtureDef fixtureDef;
    fixtureDef.shape = &circle;
    fixtureDef.density = 0.5f;
    fixtureDef.friction = 0.4f;
    body->CreateFixture(&fixtureDef);
    
    //rotate sprite randomly
    body->SetTransform(body->GetPosition(), CC_RADIANS_TO_DEGREES(arc4random() * M_PI));
    
    //give it some resistance
    body->SetLinearDamping(5);
    body->SetAngularDamping(3);
    
    //link sprite to physic body
    [sprite setPhysicsBody:body];
}


-(id) init{
	if( (self=[super init])) {
		
		// enable events
		self.isTouchEnabled = YES;
		self.isAccelerometerEnabled = YES;

		// init physics
		[self initPhysics];
        
        [self initAudioRecoder];

        for(int i=0;i<48;i++){
            [self addLeaf];
        }
        
		// begin the main run loop,  a call to [self update]
		[self scheduleUpdate];
	}
	return self;
}

-(void) dealloc{
	delete world;
	world = NULL;
	
	delete m_debugDraw;
	m_debugDraw = NULL;
	
	[super dealloc];
}	

-(void) initPhysics{
	
	b2Vec2 gravity;
	gravity.Set(0.0f, 0.0f);
	world = new b2World(gravity);
	
	// Do we want to let bodies sleep?
	world->SetAllowSleeping(true);
	world->SetContinuousPhysics(true);
	
	m_debugDraw = new GLESDebugDraw( PTM_RATIO );
	world->SetDebugDraw(m_debugDraw);
	
	uint32 flags = 0;
	flags += b2Draw::e_shapeBit;
	//		flags += b2Draw::e_jointBit;
	//		flags += b2Draw::e_aabbBit;
	//		flags += b2Draw::e_pairBit;
	//		flags += b2Draw::e_centerOfMassBit;
	m_debugDraw->SetFlags(flags);		
}

- (void)blowDetected:(float) level {
    
    CGSize winSize = [[CCDirector sharedDirector] winSize];
    CGFloat winMidY = winSize.height / 2;
    CGFloat winX = winSize.width;
    
    for(b2Body *b = world->GetBodyList(); b; b=b->GetNext()){
        // we don't want every leaf being blown every time in an attempt at a bit of realism
        if(arc4random() % 10 < 3){
            //get body position
            b2Vec2 bPos = b->GetPosition();
            // convert into cocos2d co-ordinates
            bPos *= PTM_RATIO;
            // get the vector from the microphone to the leaf
            b2Vec2 vectorFromBlow = b2Vec2(winX - bPos.x, winMidY - bPos.y);
            // normalise the vector and multiply it with a force
            vectorFromBlow.Normalize();
            vectorFromBlow *= -10 * level;
            // add force to the body
            b->ApplyLinearImpulse(vectorFromBlow, b->GetPosition());
        }
    }
}

- (void) initAudioRecoder {
    
    //The primary function of AVAudioRecorder is, as the name implies, to record audio. As a secondary function it provides audio-level information. So, here we discard the audio input by dumping it to the /dev/null bit bucket — while I can’t find any documentation to support it, the consensus seems to be that /dev/null will perform the same as on any Unix — and explicitly turn on audio metering.
  	NSURL *url = [NSURL fileURLWithPath:@"/dev/null"];
    
  	NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithFloat: 44100.0],                 AVSampleRateKey,
                              [NSNumber numberWithInt: kAudioFormatAppleLossless], AVFormatIDKey,
                              [NSNumber numberWithInt: 1],                         AVNumberOfChannelsKey,
                              [NSNumber numberWithInt: AVAudioQualityMax],         AVEncoderAudioQualityKey,
                              nil];
    
  	NSError *error;
    
  	recorder = [[AVAudioRecorder alloc] initWithURL:url settings:settings error:&error];
    
  	if (recorder) {
  		[recorder prepareToRecord];
  		recorder.meteringEnabled = YES;
  		[recorder record];
        levelTimer = [NSTimer scheduledTimerWithTimeInterval: 0.03 target: self selector: @selector(levelTimerCallback:) userInfo: nil repeats: YES];
  	} else {
  		NSLog(@"%@", [error description]);
    }
}

- (void)levelTimerCallback:(NSTimer *)timer {
	[recorder updateMeters];
    
	const double ALPHA = 0.05;
	double peakPowerForChannel = pow(10, (0.05 * [recorder peakPowerForChannel:0]));
	lowPassResults = ALPHA * peakPowerForChannel + (1.0 - ALPHA) * lowPassResults;
    
    if (lowPassResults > 0.80){
        [self blowDetected:lowPassResults];
    }
}

-(void) draw{
	//
	// IMPORTANT:
	// This is only for debug purposes & it is recommend to disable it
	//
	[super draw];
	
	ccGLEnableVertexAttribs( kCCVertexAttribFlag_Position );
	kmGLPushMatrix();
	world->DrawDebugData();
	kmGLPopMatrix();
}

-(void) update: (ccTime) dt{
	//It is recommended that a fixed time step is used with Box2D for stability
	//of the simulation, however, we are using a variable time step here.
	//You need to make an informed choice, the following URL is useful
	//http://gafferongames.com/game-physics/fix-your-timestep/
	
	int32 velocityIterations = 8;
	int32 positionIterations = 1;
	
	// Instruct the world to perform a single step of simulation. It is
	// generally best to keep the time step and iterations fixed.
	world->Step(dt, velocityIterations, positionIterations);	
}

@end
